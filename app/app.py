import os
import secrets
import subprocess
import logging
import sqlite3
import requests

from datetime import datetime
from uuid import uuid4

from flask import Flask, jsonify, request, send_from_directory, render_template
from ddtrace.appsec.track_user_sdk import (
    track_login_failure,
    track_login_success,
    track_user,
)

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
    handlers=[
        logging.FileHandler('/var/log/app.log'),
        logging.StreamHandler()
    ]
)

app = Flask(__name__)
logger = logging.getLogger(__name__)

DB_PATH = '/tmp/playground.db'


def init_db():
    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()
    cursor.execute('''
        CREATE TABLE IF NOT EXISTS users (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            username TEXT NOT NULL,
            login TEXT NOT NULL UNIQUE,
            password TEXT NOT NULL
        )
    ''')
    users = [
        ('Alice Johnson', 'alice', 'password123'),
        ('Bob Smith', 'bob', 'hunter2'),
        ('Charlie Admin', 'admin', 'admin'),
        ('Dave Wilson', 'dave', 'letmein'),
    ]
    for name, login, password in users:
        cursor.execute(
            "INSERT OR IGNORE INTO users (username, login, password) VALUES (?, ?, ?)",
            (name, login, password)
        )
    conn.commit()
    conn.close()
    logger.info("Database initialized with seed users")


init_db()

# Seeded users + session store for the shi-rce-malware-python scenario. Kept
# separate from the sqlite `users` table used by the legacy /login route
# (which stays deliberately SQL-injectable) so the two demos don't interact.
RASP_DEMO_PASSWORD = 'dogfooding-password'
rasp_users = {
    'alice': {'user_id': str(uuid4())},
    'bob': {'user_id': str(uuid4())},
}
rasp_sessions = {}


@app.before_request
def track_rasp_user():
    # Attributes RASP-scenario requests to a real account (usr.id / usr.login /
    # usr.session_id) when a valid bearer token is presented, mirroring the
    # appsec.SetUser call in the Go appsec-test-api's auth middleware.
    authorization = request.headers.get('Authorization', '')
    scheme, _, token = authorization.partition(' ')
    if scheme.lower() != 'bearer' or not token:
        return

    session = rasp_sessions.get(token)
    if session is None:
        return

    track_user(session['username'], session['user_id'], session_id=session['session_id'])


@app.route("/", methods=["GET"])
def index():
    return render_template('index.html')


@app.route("/ping", methods=["GET"])
def ping():
    logger.info(f"Ping request received from {request.remote_addr}")
    return "pong\n"


@app.route("/inject", methods=["GET", "POST"])
def inject():
    if request.method == "GET":
        data = request.args.get("cmd", "")
    elif request.method == "POST":
        data = request.get_data().decode() if request.get_data() else ""
    
    logger.info(f"Received injection request from {request.remote_addr}")
    
    if not data:
        return "No command provided", 400
    
    logger.info(f"Executing command: {data}")
    
    try:
        process = subprocess.Popen(
            data, shell=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        stdout = process.stdout.read().decode()
        stderr = process.stderr.read().decode()
        
        logger.info(f"Command executed successfully. Exit code: {process.returncode}")
        if stderr:
            logger.warning(f"Command stderr: {stderr}")

        output = f"{stdout}\n"
        output += f"{stderr}\n"
        return f"{output}"
    except Exception as e:
        logger.error(f"Error executing command: {str(e)}", exc_info=True)
        raise


@app.route("/rasp/login", methods=["POST"])
def rasp_login():
    username = request.args.get("username", "")
    password = request.args.get("password", "")
    logger.info(f"RASP login attempt for user: {username}")

    user = rasp_users.get(username)
    if user is None or password != RASP_DEMO_PASSWORD:
        track_login_failure(username, exists=user is not None)
        return jsonify({"error": "Invalid user password combination"}), 403

    track_login_success(username, user["user_id"])
    token = secrets.token_urlsafe(32)
    rasp_sessions[token] = {
        "username": username,
        "user_id": user["user_id"],
        "session_id": str(uuid4()),
    }
    return jsonify({
        "message": "Login successful",
        "access_token": token,
        "token_type": "bearer",
    })


@app.route("/rasp/shi", methods=["GET"])
def rasp_shi():
    # Deliberately vulnerable to Shell Injection, mirroring raspSHIHandler in
    # the Go appsec-test-api (appsec/test_apis/go/gin/cmd/server/main.go):
    # user input is concatenated into a shell command with no sanitization.
    command = request.args.get("command", "")
    logger.info(f"RASP SHI probe with command: {command}")
    try:
        result = subprocess.run(
            f"echo {command}",
            shell=True,
            capture_output=True,
            text=True,
            timeout=0.3,
        )
        return jsonify({"status": "ok", "sink": "shi", "input": command, "output": result.stdout})
    except (OSError, subprocess.SubprocessError) as e:
        return jsonify({"status": "ok", "sink": "shi", "input": command, "error": str(e)})


@app.route("/ssrf", methods=["GET"])
def ssrf():
    url = request.args.get("url")
    logger.info(f"Received SSRF request from {request.remote_addr} with URL: {url}")
    try:
        response = requests.get(f"http://{url}/safe")
        return response.text
    except Exception as e:
        logger.error(f"Error executing SSRF request: {str(e)}", exc_info=True)
        raise


@app.route("/lfi", methods=["GET"])
def lfi():
    filename = request.args.get("filename", "").strip()
    logger.info(f"Received LFI request from {request.remote_addr} with filename: {filename}")
    try:
        with open(filename, "r") as file:
            return file.read()
    except Exception as e:
        logger.error(f"Error executing LFI request: {str(e)}", exc_info=True)
        raise


@app.route("/login", methods=["GET"])
def login():
    user_login = request.args.get("login", "")
    password = request.args.get("password", "")
    logger.info(f"Received login request from {request.remote_addr} for user: {user_login}")

    if not user_login or not password:
        return "Missing login or password\n", 400

    try:
        conn = sqlite3.connect(DB_PATH)
        cursor = conn.cursor()
        query = f"SELECT * FROM users WHERE login = '{user_login}' AND password = '{password}'"
        logger.info(f"Executing query: {query}")
        cursor.execute(query)
        user = cursor.fetchone()
        conn.close()

        if user:
            return f"Welcome, {user[1]}!\n"
        else:
            return "Invalid credentials\n", 401
    except Exception as e:
        logger.error(f"Error executing login: {str(e)}", exc_info=True)
        raise


@app.route("/assets/<path:filename>", methods=["GET"])
def serve_asset(filename):
    return send_from_directory('/app/assets', filename)


if __name__ == '__main__':
    logger.info("Starting Flask application")
    logger.info("Application running on 0.0.0.0")
    app.run(host='0.0.0.0')
