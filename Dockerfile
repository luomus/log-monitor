FROM rocker/r-ver:4.1.0

RUN install2.r -s -e \
      dplyr \
      forcats \
      fs \
      ggplot2 \
      glue \
      memoise \
      purrr \
      readr \
      scales \
      shiny \
      shinydashboard \
      tidyr

RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      curl \
 && apt-get autoremove -y \
 && apt-get autoclean -y \
 && rm -rf /var/lib/apt/lists/*

HEALTHCHECK --interval=1m --timeout=10s \
  CMD curl -sfh -o /dev/null 0.0.0.0:3838 || exit 1

ENV HOME /home/user

COPY entrypoint.sh /usr/local/bin/entrypoint.sh

COPY app.R /home/user/shiny/app.R

RUN  mkdir -p /home/user/logs \
  && mkdir -p /home/user/plots \
  && chgrp -R 0 /home/user \
  && chmod -R g=u /home/user /etc/passwd

WORKDIR /home/user

USER 1000

EXPOSE 3838

ENTRYPOINT ["entrypoint.sh"]

CMD ["R", "-e", "shiny::runApp('~/shiny', port = 3838, host = '0.0.0.0')"]
