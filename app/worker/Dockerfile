FROM python:3.9-slim

WORKDIR /app

COPY app.py .

# Install any needed packages specified in requirements.txt
# In this case, we don't have any external dependencies

# Make port 80 available to the world outside this container
EXPOSE 80

# Run app.py when the container launches
CMD ["python", "app.py"]
