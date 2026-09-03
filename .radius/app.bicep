extension radius

param environment string

@secure()
param postgresPassword string

@description('Password/token for the OCI registry the containerImages recipe pushes to (a GitHub token with write:packages for ghcr.io).')
@secure()
param registryPassword string

@description('Username for the OCI registry the containerImages recipe pushes to (the GitHub actor for ghcr.io).')
@secure()
param registryUsername string

resource exampleVotingApp 'Radius.Core/applications@2025-08-01-preview' = {
  name: 'example-voting-app'
  properties: {
    environment: environment
  }
}

resource postgresDb 'Radius.Data/postgreSqlDatabases@2025-08-01-preview' = {
  name: 'postgres'
  properties: {
    application: exampleVotingApp.id
    codeReference: 'result/server.js#L21'
    database: 'votes'
    environment: environment
    password: postgresPassword
    username: 'postgres'
  }
}

resource redisCache 'Radius.Data/redisCaches@2025-08-01-preview' = {
  name: 'redis'
  properties: {
    application: exampleVotingApp.id
    codeReference: 'vote/app.py#L20'
    environment: environment
  }
}

resource postgresClientCredentials 'Radius.Security/secrets@2025-08-01-preview' = {
  name: 'postgres-client-credentials'
  properties: {
    application: exampleVotingApp.id
    codeReference: 'result/server.js#L24'
    data: {
      password: {
        value: postgresPassword
      }
    }
    environment: environment
  }
}

resource registryCreds 'Radius.Security/secrets@2025-08-01-preview' = {
  name: 'radius-ghcr-registry-creds'
  properties: {
    application: exampleVotingApp.id
    codeReference: '.radius/app.bicep'
    data: {
      password: {
        value: registryPassword
      }
      username: {
        value: registryUsername
      }
    }
    environment: environment
  }
}

resource resultImage 'Radius.Compute/containerImages@2025-08-01-preview' = {
  name: 'result-image'
  properties: {
    application: exampleVotingApp.id
    build: {
      platforms: [
        'linux/amd64'
      ]
      source: 'git::https://github.com/sk593/example-voting-app.git//result?ref=5b38d34d91d5ae67f3091454b1b00867cfeac20a'
    }
    codeReference: 'result/Dockerfile'
    environment: environment
    tag: '5b38d34d91d5ae67f3091454b1b00867cfeac20a'
  }
  dependsOn: [
    registryCreds
  ]
}

resource voteImage 'Radius.Compute/containerImages@2025-08-01-preview' = {
  name: 'vote-image'
  properties: {
    application: exampleVotingApp.id
    build: {
      platforms: [
        'linux/amd64'
      ]
      source: 'git::https://github.com/sk593/example-voting-app.git//vote?ref=5b38d34d91d5ae67f3091454b1b00867cfeac20a'
    }
    codeReference: 'vote/Dockerfile'
    environment: environment
    tag: '5b38d34d91d5ae67f3091454b1b00867cfeac20a'
  }
  dependsOn: [
    registryCreds
  ]
}

resource workerImage 'Radius.Compute/containerImages@2025-08-01-preview' = {
  name: 'worker-image'
  properties: {
    application: exampleVotingApp.id
    build: {
      source: 'git::https://github.com/sk593/example-voting-app.git//worker?ref=5b38d34d91d5ae67f3091454b1b00867cfeac20a'
    }
    codeReference: 'worker/Dockerfile'
    environment: environment
    tag: '5b38d34d91d5ae67f3091454b1b00867cfeac20a'
  }
  dependsOn: [
    registryCreds
  ]
}

resource resultContainer 'Radius.Compute/containers@2025-08-01-preview' = {
  name: 'result'
  properties: {
    application: exampleVotingApp.id
    codeReference: 'result/server.js#L80'
    containers: {
      result: {
        env: {
          POSTGRES_DB: {
            value: 'votes'
          }
          POSTGRES_HOST: {
            value: postgresDb.properties.host
          }
          POSTGRES_PASSWORD: {
            valueFrom: {
              secretKeyRef: {
                key: 'password'
                secretName: postgresClientCredentials.name
              }
            }
          }
          POSTGRES_SSLMODE: {
            value: 'require'
          }
          POSTGRES_USER: {
            value: 'postgres'
          }
        }
        image: resultImage.properties.imageReference
        ports: {
          web: {
            containerPort: 80
          }
        }
      }
    }
    environment: environment
  }
}

resource voteContainer 'Radius.Compute/containers@2025-08-01-preview' = {
  name: 'vote'
  properties: {
    application: exampleVotingApp.id
    codeReference: 'vote/app.py#L13'
    containers: {
      vote: {
        env: {
          REDIS_URL: {
            valueFrom: {
              secretKeyRef: {
                key: 'url'
                secretName: redisCache.properties.secrets.name
              }
            }
          }
        }
        image: voteImage.properties.imageReference
        ports: {
          web: {
            containerPort: 80
          }
        }
      }
    }
    environment: environment
  }
}

resource workerContainer 'Radius.Compute/containers@2025-08-01-preview' = {
  name: 'worker'
  properties: {
    application: exampleVotingApp.id
    codeReference: 'worker/Program.cs#L15'
    containers: {
      worker: {
        env: {
          POSTGRES_DB: {
            value: 'votes'
          }
          POSTGRES_HOST: {
            value: postgresDb.properties.host
          }
          POSTGRES_PASSWORD: {
            valueFrom: {
              secretKeyRef: {
                key: 'password'
                secretName: postgresClientCredentials.name
              }
            }
          }
          POSTGRES_SSLMODE: {
            value: 'require'
          }
          POSTGRES_USER: {
            value: 'postgres'
          }
          REDIS_URL: {
            valueFrom: {
              secretKeyRef: {
                key: 'url'
                secretName: redisCache.properties.secrets.name
              }
            }
          }
        }
        image: workerImage.properties.imageReference
      }
    }
    environment: environment
  }
}
