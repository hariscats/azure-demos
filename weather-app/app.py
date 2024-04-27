from opencage.geocoder import OpenCageGeocode
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


# Get the OpenWeather API key and OpenCage API key from environment variables
openweather_api_key = os.getenv('OPENWEATHER_API_KEY')
opencage_api_key = os.getenv('OPENCAGE_API_KEY')

if not opencage_api_key:
    raise RuntimeError("OpenCage API key not set. Please set the OPENCAGE_API_KEY environment variable.")

geocoder = OpenCageGeocode(opencage_api_key)

@app.route('/api/weather-air-quality', methods=['GET'])
def weather_air_quality():
    city = request.args.get('city')
    if not city:
        return jsonify({"error": "City parameter is required"}), 400

    # Geocode the city to get latitude and longitude
    query = geocoder.geocode(city, no_annotations='1')
    if not query:
        return jsonify({"error": "Geocoding failed, city not found"}), 404

    latitude = query[0]['geometry']['lat']
    longitude = query[0]['geometry']['lng']

    # Fetch weather data using coordinates
    weather_url = f"https://api.openweathermap.org/data/2.5/weather?lat={latitude}&lon={longitude}&appid={openweather_api_key}&units=metric"
    weather_response = requests.get(weather_url)

    # Fetch air quality data using coordinates
    air_quality_url = f"https://api.openweathermap.org/data/2.5/air_pollution?lat={latitude}&lon={longitude}&appid={openweather_api_key}"
    air_quality_response = requests.get(air_quality_url)

    if weather_response.status_code != 200 or air_quality_response.status_code != 200:
        return jsonify({"error": "Failed to fetch data"}), 500

    weather_data = weather_response.json()
    air_quality_data = air_quality_response.json()

    return jsonify({"weather": weather_data, "air_quality": air_quality_data})


if __name__ == '__main__':
    app.run(debug=True)
