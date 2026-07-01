FROM registry.gitlab.com/debdistutils/guix/container:latest

# Start the Guix daemon in the background during build if needed,
# but we can rely on runtime guix shell resolution.
WORKDIR /workspace

# Copy the workspace files
COPY . /workspace

# Expose /tmp so the host can mount it and access /tmp/gaia.sock
VOLUME /tmp

# Run the GAIA server using the Guix manifest
ENTRYPOINT ["guix", "shell", "-m", "guix.scm", "--", "./bin/gaia-server"]
