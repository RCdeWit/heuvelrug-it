import subprocess

from utils.find_project_root import find_project_root

PROJECT_ROOT = find_project_root()

def get_terraform_output(tf_output_name) -> str:

    if tf_output_name is None:
        raise ValueError('tf_output_name not specified')

    result = subprocess.run(
        ["terraform", "output", "-raw", tf_output_name],
        cwd=f"{PROJECT_ROOT}/terraform",
        stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL,
        text=True,
    )
    return result.stdout.strip()