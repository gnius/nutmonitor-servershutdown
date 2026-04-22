FROM debian:bookworm-slim

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
      bash \
      nut-client \
      openssh-client \
      msmtp \
      ca-certificates && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /app
COPY monitor.sh /app/monitor.sh
RUN chmod +x /app/monitor.sh

CMD ["/app/monitor.sh"]
