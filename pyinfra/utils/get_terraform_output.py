import subprocess

from utils.find_project_root import find_project_root

PROJECT_ROOT = find_project_root()

def get_terraform_output(tf_output_name) -> str:

    if tf_output_name is None:
        raise ValueError('tf_output_name not specified')

    terraform_output = subprocess.run(["terraform", "output", tf_output_name], cwd=f"{PROJECT_ROOT}/terraform", capture_output=True, text=True).stdout
    terraform_output = terraform_output.replace('"', '').replace('\n', '')

    return terraform_output