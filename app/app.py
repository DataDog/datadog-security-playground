import os
import subprocess
import logging
import sqlite3
import requests

from datetime import datetime

from flask import Flask, request, send_from_directory, render_template

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
