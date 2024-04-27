import os
from flask import Flask, jsonify
import requests

app = Flask(__name__)

@app.route('/weather/<city>')
def weather(city):
    api_key = os.getenv('WEATHER_API_KEY')
    if not api_key:
        return jsonify({"error": "API key not configured"}), 403
    url = f"http://api.openweathermap.org/data/2.5/weather?q={city}&appid={api_key}"
    response = requests.get(url)
    data = response.json()
    return jsonify(data)

if __name__ == '__main__':
    app.run(debug=True)
