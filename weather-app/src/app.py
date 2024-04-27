from flask import Flask, request, jsonify
import requests
import os
from opencage.geocoder import OpenCageGeocode

# Initialize the Flask app
app = Flask(__name__)

# Fetch and validate API keys from environment variables
openweather_api_key = os.getenv('OPENWEATHER_API_KEY')
opencage_api_key = os.getenv('OPENCAGE_API_KEY')
if not openweather_api_key or not opencage_api_key:
    raise EnvironmentError("API keys not set. Please ensure OPENWEATHER_API_KEY and OPENCAGE_API_KEY are configured.")

# Initialize the geocoder with the OpenCage API key
geocoder = OpenCageGeocode(opencage_api_key)

def fetch_weather_data(url):
    """ Fetch data from OpenWeatherMap API using a constructed URL.
    Args:
        url (str): The URL to fetch the data from.
    Returns:
        dict: JSON response from the API call.
    """
    response = requests.get(url)
    if response.status_code == 200:
        return response.json()
    else:
        return {"error": "Failed to fetch data from OpenWeatherMap", "status_code": response.status_code}

@app.route('/api/weather', methods=['GET'])
def get_weather():
    """ API endpoint to fetch current weather data for a specified city.
    Uses query parameter 'city' to specify the location.
    Returns:
        JSON response containing weather data or an error message.
    """
    city = request.args.get('city', default="London")
    url = f"https://api.openweathermap.org/data/2.5/weather?q={city}&appid={openweather_api_key}&units=metric"
    data = fetch_weather_data(url)
    return jsonify(data)

@app.route('/api/forecast', methods=['GET'])
def get_forecast():
    """ API endpoint to fetch weather forecast data for a specified city.
    Uses query parameter 'city' to specify the location. It returns a 5-day forecast.
    Returns:
        JSON response containing forecast data or an error message.
    """
    city = request.args.get('city')
    if not city:
        return jsonify({"error": "City parameter is required"}), 400

    url = f"http://api.openweathermap.org/data/2.5/forecast?q={city}&appid={openweather_api_key}&units=metric"
    forecast_data = fetch_weather_data(url)
    if "error" in forecast_data:
        return jsonify(forecast_data), forecast_data.get("status_code", 500)

    forecasts = [{'time': f['dt_txt'], 'temperature': f['main']['temp'], 'description': f['weather'][0]['description']}
                 for f in forecast_data.get('list', [])]
    return jsonify({"city": city, "forecasts": forecasts})

@app.route('/api/weather-air-quality', methods=['GET'])
def weather_air_quality():
    """ API endpoint to fetch both weather and air quality data for a specified city.
    Uses geocoding to convert the city name to latitude and longitude, then fetches data.
    Returns:
        JSON response containing both weather and air quality data or an error message.
    """
    city = request.args.get('city')
    if not city:
        return jsonify({"error": "City parameter is required"}), 400

    # Geocode the city to get latitude and longitude
    query = geocoder.geocode(city, no_annotations='1')
    if not query:
        return jsonify({"error": "Geocoding failed, city not found"}), 404

    latitude = query[0]['geometry']['lat']
    longitude = query[0]['geometry']['lng']
    weather_url = f"https://api.openweathermap.org/data/2.5/weather?lat={latitude}&lon={longitude}&appid={openweather_api_key}&units=metric"
    air_quality_url = f"https://api.openweathermap.org/data/2.5/air_pollution?lat={latitude}&lon={longitude}&appid={openweather_api_key}"

    weather_data = fetch_weather_data(weather_url)
    air_quality_data = fetch_weather_data(air_quality_url)
    if "error" in weather_data or "error" in air_quality_data:
        return jsonify({"weather_error": weather_data.get("error"), "air_quality_error": air_quality_data.get("error")}), 500

    return jsonify({"weather": weather_data, "air_quality": air_quality_data})

if __name__ == '__main__':
    app.run(debug=True)
