import os
import subprocess
import logging
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


@app.route("/", methods=["GET"])
def index():
    return render_template('index.html')


@app.route("/ping", methods=["GET"])
def ping():
    logger.info(f"Ping request received from {request.remote_addr}")
    return "pong\n"


@app.route("/inject", methods=["GET"])
def inject():
    data = request.args.get("cmd")
    logger.info(f"Received injection request from {request.remote_addr}")
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
        response = requests.get(url)
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


@app.route("/assets/<path:filename>", methods=["GET"])
def serve_asset(filename):
    return send_from_directory('/app/assets', filename)


if __name__ == '__main__':
    logger.info("Starting Flask application")
    logger.info("Application running on 0.0.0.0")
    app.run(host='0.0.0.0')
