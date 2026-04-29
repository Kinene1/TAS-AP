<p align="center">
  <img src="tas_icon.png" alt="Logo" width="150"/>
</p>

<h1 align="center">Targeted Amplicon Sequencing Analysis Pipeline (TAS-AP)</h1>

TAS-AP is a user-friendly desktop application for analysing Nanopore targeted amplicon sequencing data across any supported primer scheme.
It integrates established ARTIC bioinformatics workflows with Nextstrain phylogenetic analysis, providing an end-to-end solution from read processing to tree visualisation.

The pipeline can be run either as a script or through a graphical user interface (GUI). The graphical user interface (GUI) allows users to customise key pipeline parameters, monitor progress, and access outputs without command-line interaction, while a full command-line mode remains available for advanced users. 

## **Installation**
A pre-compiled Linux x86-64 binary is provided for straightforward setup. Download and extract the tarball, then run the installation script in the terminal as shown below:

<pre> 
  wget https://github.com/Kinene1/TAS-AP/releases/download/v1.0.0/tas_ap_v1.0.0-linux-x86-64-binaries.tar.gz
  tar -xvf tas_ap_v1.0.0-linux-x86-64-binaries.tar.gz
  cd tas_ap_v1.0.0-linux-x86-64-binaries
  bash install.sh
</pre>

The installation script will:
•	-Item 1 Create and configure the required Conda environment
•	-Install all pipeline dependencies
•	-Set executable permissions
•	-Generate a desktop launcher for the TAS-AP GUI

<p align="center">
  <img src="tas_icon.png" alt="Logo" width="150"/>
</p>

<h1 align="center">Targeted Amplicon Sequencing Analysis Pipeline (TAS-AP)</h1>
