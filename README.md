<h1 align="center">
  <span style="display: inline-flex; align-items: center; gap: 12px;">
    <img src="tas_icon.png" alt="Logo" width="100" style="margin-top: 8px;"/>
    <span>
      Targeted Amplicon Sequencing Analysis Pipeline (TAS-AP)
    </span>
  </span>
</h1>

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
- Create and configure the required Conda environment
- Install all pipeline dependencies
- Set executable permissions
- Generate a desktop launcher for the TAS-AP GUI
Once the installation completes, TAS-AP can be started either from the desktop icon or via the command line.
To launch the GUI, open **Show Applications**, click on “**Type to search**”, and enter **TAS Analysis Pipeline**.
When the application appears in the results, click the icon to start the GUI.

<h2> Running the TAS-AP remotely </h2>
If you are accessing the application on a remote system, open a terminal and launch the GUI with one of the following commands:
<pre>
  cd tas_ap_v1.0.0-linux-x86-64-binaries
  ./dist/tas_gui  
</pre>
or 
<pre>
  cd tas_ap_v1.0.0-linux-x86-64-binaries
  conda activate tas-pipeline
  Python tas_gui.py
</pre>
This will open the TAS-AP GUI, allowing you to load the required inputs and run the pipeline.

<h3> Running TAS-AP on a Dataset </h3>

1.	**Select the input FASTQ directory**.

    Navigate to the directory containing the demultiplexed Nanopore reads (the `fastq_pass` directory). <br>
  	Double-click the directory so that the individual barcode folders are visible, then click OK. <br>
    
2.	**Enter the Run/Sample prefix**. <br>
    This is the job name used to label output files. It can be any descriptive name.
  	
3.	**Set amplicon length thresholds**. <br>
    Specify the minimum and maximum amplicon lengths, allowing a ±200 bp buffer around the expected size.
  
4.	**Provide the `sample_metadata.tsv` file.** <br>
    This file maps barcodes to sample IDs and must be named exactly `sample_metadata.tsv`.<br>
  	It should contain the following headers:
    <pre>
  	barcode	sample_id
    barcode01	sample_A
    barcode02	sample_B
    </pre>
    
5.	**Select the primer scheme BED file.** For example: `ps.scheme.bed`.
   
6.	**Select the corresponding reference FASTA file.** <br>
    This must match the chosen primer scheme (e.g., `ps.reference.fasta`).
  	
7.  **Run the pipeline.** <br>
    After all inputs are set, click **Run Pipeline** to start the analysis. <br>
    The GUI will display progress and generate outputs once processing is complete.


      
