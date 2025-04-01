FROM aztecprotocol/foundry:25f24e677a6a32a62512ad4f561995589ac2c7dc AS foundry

FROM go-nitro:latest
COPY --from=foundry /opt/foundry/bin/* /usr/local/bin/

RUN apt-get update
RUN apt-get install -y wget jq curl
RUN rm -rf /var/lib/apt/lists/*
WORKDIR /tmp
RUN wget https://github.com/txtx/txtx/releases/latest/download/txtx-linux-x64.tar.gz && \
  tar zxvf txtx-linux-x64.tar.gz && \
  mv txtx /usr/local/bin && \
  rm -f txtx-linux-x64.tar.gz

COPY nitro-contracts-runbook /opt/nitro-contracts-runbook

RUN mkdir -p /opt/entrypoint
COPY run.sh /opt/entrypoint

ENTRYPOINT ["/opt/entrypoint/run.sh"]