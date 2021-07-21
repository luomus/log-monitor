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

CMD ["R", "-e", "shiny::runApp('/home/user/shiny', port = 3838, host = '0.0.0.0')"]
