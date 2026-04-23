# Appliance-server-validation-tool

## Directory Structure

Your directory should look like this:

```
.
├── Dockerfile
├── entrypoint.sh
├── README.md
└── scripts
    ├── ACS_disable.sh
    ├── ACS_enable.sh
    ├── rngd-diag
    ├── rngd-diag_decoder.py
    ├── run_diag.sh
    ├── run_p2p.sh
    └── run_stress.sh
```

> **Note:**  
> If your actual `HOME` directory differs from the default `/home/furiosa`, make sure to update the following lines in the `Dockerfile` to reflect your environment:
>
> - **line 11:**  
>   `ENV HOME=/home/furiosa`
> - **line 48:**  
>   `ENTRYPOINT ["/home/furiosa/appliance-server-validation-tool/entrypoint.sh"]`
>
> Adjust these to match your actual home directory (and path to `entrypoint.sh`) so the tool functions correctly.

## Required Environment Variable

Before building or running the Docker image, **you must export your Hugging Face access token** as the `HF_TOKEN` environment variable in your shell:

```bash
export HF_TOKEN=your_huggingface_token
```

Replace `your_huggingface_token` with your actual Hugging Face access token.  
The build process and some scripts will fail if `HF_TOKEN` is not set.  
For more information or to obtain a token, visit [https://huggingface.co/settings/tokens](https://huggingface.co/settings/tokens).

> **Important:**  
> To run the LLM validation (stress test), your Hugging Face account must have accepted the terms of use for the model(s) specified in `scripts/run_stress.sh`.  
> 
> Specifically, you need access to:
> - [`meta-llama/Llama-3.1-8B-Instruct`](https://huggingface.co/meta-llama/Llama-3.1-8B-Instruct)
>
> Visit the Hugging Face model pages above and agree to their terms if you have not already.  
> Your Hugging Face token (`HF_TOKEN`) must have permission to download these models for the tool to function correctly.

## Build Docker Image

You can now build the Docker image with the command below:

```bash
docker build --progress=plain --build-arg HF_TOKEN=$HF_TOKEN -t furiosa-validation-tool-online:[version] .
```

## Run Docker Image

To run the Docker image, use the following command:

```bash
docker run --rm -it --privileged \
  -v /sys/kernel/debug:/sys/kernel/debug \
  -v /lib/modules:/lib/modules:ro \
  -v $(pwd)/outputs:{output_directory} \
  -v $(pwd)/logs:{log_directory} \
  -e RUN_TESTS=diag,stress \
  furiosa-validation-tool-online:{version}
```

**Example**:

Here is a sample command for running the validation tool Docker image, mounting the output and log directories to their default locations inside the container:

```bash
docker run --rm -it --privileged \
  -v /sys/kernel/debug:/sys/kernel/debug \
  -v /lib/modules:/lib/modules:ro \
  -v $(pwd)/outputs:/home/furiosa/outputs \
  -v $(pwd)/logs:/home/furiosa/logs \
  -e RUN_TESTS=stress \
  furiosa-validation-tool-online:26.1.0
```

> **Note:** You can change the value of the `RUN_TESTS` environment variable to specify which tests to run.  
> For example, set `RUN_TESTS=diag,stress` to run both diagnostic and stress tests.  
> You may specify one or more test names, separated by commas, depending on which tests you wish to execute.
