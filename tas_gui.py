#!/usr/bin/env python3

import PySimpleGUI as sg
import subprocess
import os
import sys
import threading
import queue
import time
import webbrowser

# Tonny Kinene (Tonny.Kinene@dpird.wa.gov.au)

#-----------------------------------------------------------------------
# DPIRD DIagnostics and Laboratory Services
# Sustainability and Biosecurity 
# Department of Primary Industries and Regional Development
# 31 Cedric Street, Stirling WA 6021
# ----------------------------------------------------------------------

# Copyright (c) 2026 Tonny Kinene
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program. If not, see <https://www.gnu.org/licenses/>.
#------------------------------------------------------------------------


# ------------------------------
# Theme
# ------------------------------
sg.theme("LightBlue2")
AUSPICE_URL = "http://127.0.0.1:4000/auspice"

# ------------------------------
# Conda + script paths
# ------------------------------
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
CONFIG_FILE = os.path.join(SCRIPT_DIR, "last_run_info.txt")

CONDA_SH = os.path.expanduser("~/anaconda3/etc/profile.d/conda.sh")
CONDA_ENV = "tas-pipeline"

PIPELINE_SCRIPT = os.path.join(SCRIPT_DIR, "run_pipeline.sh")
PHYLO_SCRIPT = os.path.join(SCRIPT_DIR, "run_phylo3.sh")

#LOGO_PATH = os.path.join(SCRIPT_DIR, "tas_icon.png")


# ------------------------------
# Pipeline stages
# ------------------------------
STAGES = [
    "Guppyplex",
    "Artic Minion",
    "Metadata + Reporting",
    "Consensus Collection",
    "Genome Recovery",
    "PDF Generation",
    "Completed"
]
TOTAL_STAGES = len(STAGES)

# ------------------------------
# GUI Layout
# ------------------------------
layout = [
    [sg.Text("TAS Analysis Pipeline", font=("Helvetica", 16))],

    [sg.Text("Input FASTQ directory:"), sg.Input(key="-BASE_DIR-", size=(40, 1)), sg.FolderBrowse()],
    [sg.Text("Run / Sample prefix:"), sg.Input(key="-RUN_PREFIX-", size=(25, 1))],

    [sg.Text("Min read length:"), sg.Input("250", size=(8, 1), key="-MIN_LEN-"),
     sg.Text("Max read length:"), sg.Input("1500", size=(8, 1), key="-MAX_LEN-")],

    [sg.Text("Metadata TSV (optional):"), sg.Input(key="-METADATA_FILE-", size=(40, 1)),
     sg.FileBrowse(file_types=(("TSV files", "*.tsv"),))],

    [sg.Text("BED file (optional):"), sg.Input(key="-BED_FILE-", size=(40, 1)),
     sg.FileBrowse(file_types=(("BED files", "*.bed"),))],

    [sg.Text("Reference FASTA (optional):"), sg.Input(key="-REF_FILE-", size=(40, 1)),
     sg.FileBrowse(file_types=(("FASTA files", "*.fasta"),))],

    [sg.HorizontalSeparator()],

    [sg.Text("Pipeline Progress:", font=("Helvetica", 10, "bold"))],
    [sg.ProgressBar(TOTAL_STAGES, orientation='h', size=(50, 20), key='-PROGRESS-', bar_color=("white", "blue"))],
    [sg.Text("Stage: Idle", key="-STAGE-", size=(60, 1))],
    [sg.Text("Estimated time remaining: --:--", key="-ETA-", size=(60, 1))],

    [sg.HorizontalSeparator()],

    [sg.Text("Phylogeny Progress:", font=("Helvetica", 10, "bold"))],
    [sg.ProgressBar(100, orientation='h', size=(50, 20), key='-PHYLO-PROGRESS-', bar_color=("white", "gray"))],
    [sg.Text("Stage: Idle", key="-PHYLO-STAGE-", size=(60, 1))],

    [sg.HorizontalSeparator()],

    [sg.Multiline(size=(100, 18), key="-LOG-", autoscroll=True, disabled=True)],

    [sg.Button("Run Pipeline", key="-RUN-"),
     sg.Button("Phylogeny", key="-PHYLO-"),
     sg.Button("View Report", key="-VIEW-"),
     sg.Button("View Tree", key="-TREE-"),
     sg.Button("Exit")]
]

window = sg.Window("TAS Analysis Pipeline", layout, finalize=True)

# ------------------------------
# Globals
# ------------------------------
process = None
phylo_process = None
auspice_process = None
log_queue = queue.Queue()

current_stage_index = 0
pipeline_start_time = None
substage_animation = ["", ".", "..", "..."]
animation_index = 0

# ------------------------------
# Helper functions
# ------------------------------
def open_file_safely(filepath):
    if not os.path.isfile(filepath):
        sg.popup_error(f"File not found:\n{filepath}")
        return
    env = os.environ.copy()
    env.pop("LD_LIBRARY_PATH", None)
    try:
        if sys.platform.startswith("linux"):
            subprocess.Popen(["xdg-open", filepath], env=env)
        elif sys.platform.startswith("win"):
            os.startfile(filepath)
        elif sys.platform.startswith("darwin"):
            subprocess.Popen(["open", filepath], env=env)
    except Exception as e:
        sg.popup_error(f"Could not open file:\n{e}")


def update_progress(stage_name):
    global current_stage_index
    if stage_name in STAGES:
        current_stage_index = STAGES.index(stage_name) + 1
        color = ("white", "green") if stage_name == "Completed" else ("white", "yellow")
        window['-PROGRESS-'].update(current_stage_index, bar_color=color)
        window['-STAGE-'].update(f"Stage: {stage_name}")


def detect_stage_from_output(line):
    if "Running guppyplex" in line:
        update_progress("Guppyplex")
    elif "Running artic minion" in line:
        update_progress("Artic Minion")
    elif "Coverage Summary Report" in line or "Loading metadata" in line:
        update_progress("Metadata + Reporting")
    elif "Collecting consensus" in line:
        update_progress("Consensus Collection")
    elif "Genome Recovery Summary" in line or "Reference genome length" in line:
        update_progress("Genome Recovery")
    elif "Generating PDF" in line:
        update_progress("PDF Generation")
    elif "All processing complete" in line:
        update_progress("Completed")


def run_subprocess(command, env=None, phylo=False):
    global process, phylo_process
    try:
        proc = subprocess.Popen(
            command,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            env=env
        )
        if phylo:
            phylo_process = proc
        else:
            process = proc

        for line in proc.stdout:
            log_queue.put((line, phylo))

        proc.wait()
        log_queue.put(("__PROCESS_DONE__", phylo))

    except Exception as e:
        log_queue.put((f"__PROCESS_ERROR__ {e}", phylo))


def start_background_process(command, env=None, phylo=False):
    thread = threading.Thread(target=run_subprocess, args=(command, env, phylo), daemon=True)
    thread.start()


def disable_buttons(state=True):
    window["-RUN-"].update(disabled=state)
    window["-PHYLO-"].update(disabled=state)


def format_eta(elapsed, completed, total):
    if completed == 0:
        return "--:--"
    avg = elapsed / completed
    remaining = avg * (total - completed)
    mins, secs = divmod(int(remaining), 60)
    return f"{mins:02d}:{secs:02d}"


def start_auspice(results_dir):
    global auspice_process
    if auspice_process and auspice_process.poll() is None:
        return
    try:
        env = os.environ.copy()
        env.pop("LD_LIBRARY_PATH", None)
        auspice_process = subprocess.Popen(
            ["auspice", "view", "--datasetDir", results_dir, "--host", "127.0.0.1"],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            env=env
        )
        time.sleep(2)
    except Exception as e:
        sg.popup_error(f"Failed to start Auspice: {e}")


def load_results_dir_from_config():
    if not os.path.isfile(CONFIG_FILE):
        return None
    with open(CONFIG_FILE) as f:
        for line in f:
            if line.startswith("RESULTS_DIR="):
                return line.strip().split("=", 1)[1]
    return None


# ------------------------------
# Event Loop
# ------------------------------
while True:
    event, values = window.read(timeout=200)

    # ETA animation
    if pipeline_start_time and 0 < current_stage_index < TOTAL_STAGES:
        animation_index = (animation_index + 1) % len(substage_animation)
        window["-STAGE-"].update(
            f"Stage: {STAGES[current_stage_index-1]} {substage_animation[animation_index]}"
        )
        elapsed = time.time() - pipeline_start_time
        window["-ETA-"].update(
            f"Estimated time remaining: {format_eta(elapsed, current_stage_index, TOTAL_STAGES)}"
        )

    # Process logs
    while not log_queue.empty():
        message, phylo = log_queue.get()
        if message == "__PROCESS_DONE__":
            disable_buttons(False)
            if phylo:
                window["-PHYLO-PROGRESS-"].update(100, bar_color=("white", "green"))
                window["-PHYLO-STAGE-"].update("Stage: Completed")
            else:
                process = None
                window["-PROGRESS-"].update(TOTAL_STAGES, bar_color=("white", "green"))
                window["-STAGE-"].update("Stage: Completed")
                window["-ETA-"].update("Estimated time remaining: 00:00")
        elif message.startswith("__PROCESS_ERROR__"):
            sg.popup_error(message.replace("__PROCESS_ERROR__", ""))
            disable_buttons(False)
        else:
            if not phylo:
                detect_stage_from_output(message)
            window["-LOG-"].update(message, append=True)

    # Exit
    if event in (sg.WINDOW_CLOSED, "Exit"):
        if process:
            process.terminate()
        if phylo_process:
            phylo_process.terminate()
        if auspice_process:
            auspice_process.terminate()
        break

    # ---------------- RUN PIPELINE ----------------
    if event == "-RUN-":
        try:
            base_dir = values.get("-BASE_DIR-")
            if not base_dir or not os.path.isdir(base_dir):
                sg.popup_error("Invalid FASTQ directory.")
                continue

            parent_dir = os.path.abspath(os.path.join(base_dir, os.pardir))
            guppyplex_results_dir = os.path.join(parent_dir, "guppyplex_results")
            results_dir = os.path.join(parent_dir, "results")
            os.makedirs(guppyplex_results_dir, exist_ok=True)
            os.makedirs(results_dir, exist_ok=True)

            with open(CONFIG_FILE, "w") as f:
                f.write(f"GUPPY_RESULTS_DIR={guppyplex_results_dir}\n")
                f.write(f"RESULTS_DIR={results_dir}\n")

            env = os.environ.copy()
            env["BASE_DIR"] = base_dir
            env["RUN_AND_SAMPLE_PREFIX"] = values.get("-RUN_PREFIX-") or "DefaultPrefix"
            env["RUN_PREFIX"] = env["RUN_AND_SAMPLE_PREFIX"]
            env["GUPPY_RESULTS_DIR"] = guppyplex_results_dir
            env["RESULTS_DIR"] = results_dir
            env["MIN_LENGTH"] = values.get("-MIN_LEN-") or "250"
            env["MAX_LENGTH"] = values.get("-MAX_LEN-") or "1500"

            if values.get("-METADATA_FILE-"):
                env["METADATA_FILE"] = values.get("-METADATA_FILE-")
            if values.get("-BED_FILE-"):
                env["BED_FILE"] = values.get("-BED_FILE-")
            if values.get("-REF_FILE-"):
                env["REF_FILE"] = values.get("-REF_FILE-")

            current_stage_index = 0
            pipeline_start_time = time.time()

            window["-PROGRESS-"].update(0, bar_color=("white", "blue"))
            window["-STAGE-"].update("Stage: Initialising...")
            window["-ETA-"].update("Estimated time remaining: calculating...")

            disable_buttons(True)

            # Run pipeline, ensure covarplot.py is in SCRIPT_DIR
            cmd = [
                "bash",
                "-c",
                f"source {CONDA_SH} && conda activate {CONDA_ENV} && cd {SCRIPT_DIR} && bash {PIPELINE_SCRIPT}"
            ]

            start_background_process(cmd, env, phylo=False)

        except Exception as e:
            sg.popup_error(f"Pipeline launch failed:\n{e}")
            disable_buttons(False)

    # ---------------- PHYLOGENY ----------------
    if event == "-PHYLO-":
        disable_buttons(True)
        window["-PHYLO-STAGE-"].update("Stage: Running...")
        window["-PHYLO-PROGRESS-"].update(5, bar_color=("white", "yellow"))

        cmd = [
            "bash",
            "-c",
            f"source {CONDA_SH} && conda activate {CONDA_ENV} && cd {SCRIPT_DIR} && bash {PHYLO_SCRIPT}"
        ]

        start_background_process(cmd, phylo=True)

    # ---------------- VIEW REPORT ----------------
    if event == "-VIEW-":
        results_dir = load_results_dir_from_config()
        if not results_dir:
            sg.popup_error("No run configuration found.")
            continue

        pdf_path = os.path.join(os.path.dirname(results_dir), "guppyplex_results", "coverage_summary_report.pdf")
        if not os.path.isfile(pdf_path):
            sg.popup_error(f"PDF not found:\n{pdf_path}")
            continue

        open_file_safely(pdf_path)

    # ---------------- VIEW TREE ----------------
    if event == "-TREE-":
        results_dir = load_results_dir_from_config()
        if not results_dir or not os.path.isdir(results_dir):
            sg.popup_error("Results directory not found. Run pipeline first.")
            continue

        start_auspice(results_dir)
        webbrowser.open(AUSPICE_URL)

window.close()
