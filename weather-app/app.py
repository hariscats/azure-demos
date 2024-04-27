from flask import Flask

app = Flask(__name__)

@app.route('/')
def home():
    return "Hello, this is your weather dashboard!"

if __name__ == '__main__':
    app.run(debug=True)
