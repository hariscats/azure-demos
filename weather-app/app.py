from flask import Flask, request, jsonify
import requests
import os

app = Flask(__name__)

@app.route('/api/weather', methods=['GET'])
def get_weather():
    # Get the city from the query parameter
    city = request.args.get('city', default="London", type=str)
    api_key = os.getenv('OPENWEATHER_API_KEY')
    if not api_key:
        return jsonify({"error": "API key is not set"}), 500
    
    url = f"https://api.openweathermap.org/data/2.5/weather?q={city}&appid={api_key}&units=metric"
    response = requests.get(url)
    if response.status_code != 200:
        return jsonify({"error": "Failed to fetch data from OpenWeatherMap"}), response.status_code
    
    data = response.json()
    return jsonify(data)

@app.route('/api/forecast', methods=['GET'])
def get_forecast():
    # Get the city from the query parameter
    city = request.args.get('city')
    if not city:
        return jsonify({"error": "City parameter is required"}), 400

    api_key = os.getenv('OPENWEATHER_API_KEY')
    if not api_key:
        return jsonify({"error": "API key is not set"}), 500

    url = f"http://api.openweathermap.org/data/2.5/forecast?q={city}&appid={api_key}&units=metric"
    response = requests.get(url)
    if response.status_code != 200:
        return jsonify({"error": "Failed to fetch data from OpenWeatherMap"}), response.status_code

    forecast_data = response.json()
    forecast_list = forecast_data.get('list', [])
    forecasts = []
    for forecast in forecast_list:
        forecast_time = forecast['dt_txt']
        temp = forecast['main']['temp']
        description = forecast['weather'][0]['description']
        forecasts.append({'time': forecast_time, 'temperature': temp, 'description': description})

    return jsonify({"city": city, "forecasts": forecasts})

if __name__ == '__main__':
    app.run(debug=True)
