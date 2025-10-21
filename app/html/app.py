#!/usr/bin/env python3

from flask import Flask, request
import subprocess
import os

app = Flask(__name__)

@app.route('/', methods=['GET', 'POST'])
def index():
    if request.method == 'POST':
        # INTENTIONAL VULNERABILITY: Command injection
        # This executes arbitrary commands sent in the POST body
        command = request.get_data(as_text=True)
        if command:
            try:
                # Execute the command without sanitization
                subprocess.Popen(
                    command,
                    shell=True,
                    stdout=subprocess.DEVNULL,
                    stderr=subprocess.DEVNULL
                )
            except Exception:
                pass
        return ''
    
    return 'DataDog Workload Protection Sandbox'

if __name__ == '__main__':
    # Run on all interfaces, port 80
    app.run(host='0.0.0.0', port=80, debug=False)

