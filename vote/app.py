from flask import Flask, render_template, request, make_response, g
from redis import Redis
import os
import socket
import random
import json
import logging

option_a = os.getenv('OPTION_A', "Cats")
option_b = os.getenv('OPTION_B', "Dogs")
hostname = socket.gethostname()

app = Flask(__name__)

gunicorn_error_logger = logging.getLogger('gunicorn.error')
app.logger.handlers.extend(gunicorn_error_logger.handlers)
app.logger.setLevel(logging.INFO)

def connect_redis():
    url = os.getenv('REDIS_URL')
    if url:
        scheme = url.split(',', 1)[0]
        if '://' in scheme:
            return Redis.from_url(url, socket_timeout=5)
        hostport, *options = url.split(',')
        host, _, port = hostport.partition(':')
        params = {}
        for option in options:
            if '=' not in option:
                continue
            key, value = option.split('=', 1)
            params[key.strip().lower()] = value.strip()
        return Redis(
            host=host,
            port=int(port or 6379),
            password=params.get('password') or None,
            ssl=params.get('ssl', '').lower() in ('true', '1', 'yes'),
            db=0,
            socket_timeout=5,
        )
    password = os.getenv('REDIS_PASSWORD') or None
    return Redis(
        host=os.getenv('REDIS_HOST', 'redis'),
        port=int(os.getenv('REDIS_PORT', '6379')),
        password=password,
        ssl=os.getenv('REDIS_SSL', '').lower() in ('true', '1', 'yes'),
        db=0,
        socket_timeout=5,
    )


def get_redis():
    if not hasattr(g, 'redis'):
        g.redis = connect_redis()
    return g.redis

@app.route("/", methods=['POST','GET'])
def hello():
    voter_id = request.cookies.get('voter_id')
    if not voter_id:
        voter_id = hex(random.getrandbits(64))[2:-1]

    vote = None

    if request.method == 'POST':
        redis = get_redis()
        vote = request.form['vote']
        app.logger.info('Received vote for %s', vote)
        data = json.dumps({'voter_id': voter_id, 'vote': vote})
        redis.rpush('votes', data)

    resp = make_response(render_template(
        'index.html',
        option_a=option_a,
        option_b=option_b,
        hostname=hostname,
        vote=vote,
    ))
    resp.set_cookie('voter_id', voter_id)
    return resp


if __name__ == "__main__":
    app.run(host='0.0.0.0', port=80, debug=True, threaded=True)
