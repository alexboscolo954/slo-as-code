FROM python:3.12-slim
RUN pip install --no-cache-dir prometheus-client==0.26.0
COPY app.py /app.py
USER 65534
ENTRYPOINT ["python", "-u", "/app.py"]
