import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:intl/intl.dart';

class WeatherWidget extends StatefulWidget {
  final bool compact;
  final WeatherData? existingWeatherData;
  final bool isLoading;
  final VoidCallback? onRefresh;

  const WeatherWidget({
    this.compact = false,
    this.existingWeatherData,
    this.isLoading = false,
    this.onRefresh,
    Key? key,
  }) : super(key: key);

  @override
  _WeatherWidgetState createState() => _WeatherWidgetState();
}

class _WeatherWidgetState extends State<WeatherWidget> {
  WeatherData? _weatherData;
  bool _isLoading = true;
  String _error = '';

  static const String WEATHER_API_KEY = 'f0dbe5113db2db758394e7351f6254d0';

  @override
  void initState() {
    super.initState();
    if (widget.existingWeatherData != null) {
      _weatherData = widget.existingWeatherData;
      _isLoading = false;
    } else if (widget.isLoading) {
      _isLoading = true;
    } else {
      _fetchWeather();
    }
  }

  @override
  void didUpdateWidget(WeatherWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.existingWeatherData != oldWidget.existingWeatherData) {
      setState(() {
        if (widget.existingWeatherData != null) {
          _weatherData = widget.existingWeatherData;
          _isLoading = false;
          _error = '';
        }
      });
    }
    if (widget.isLoading != oldWidget.isLoading) {
      setState(() {
        _isLoading = widget.isLoading;
      });
    }
  }

  Future<void> _fetchWeather() async {
    setState(() {
      _isLoading = true;
      _error = '';
    });

    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          setState(() {
            _error = 'Location permission denied';
            _isLoading = false;
          });
          return;
        }
      }

      Position position = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.medium);

      final response = await http.get(Uri.parse(
          'https://api.openweathermap.org/data/2.5/weather?lat=${position.latitude}&lon=${position.longitude}&appid=$WEATHER_API_KEY&units=metric'));

      if (response.statusCode == 200) {
        final Map<String, dynamic> data = jsonDecode(response.body);
        setState(() {
          _weatherData = WeatherData.fromJson(data);
          _isLoading = false;
          _error = '';
        });
        if (widget.onRefresh != null) {
          widget.onRefresh!();
        }
      } else {
        setState(() {
          _error = 'Failed to load weather data';
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _error = 'Error fetching weather: $e';
        _isLoading = false;
      });
    }
  }

  Widget _buildWeatherIcon(String iconCode, {double size = 50}) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF0F4C5C).withOpacity(0.2),
        shape: BoxShape.circle,
        border: Border.all(
          color: Colors.white.withOpacity(0.2),
          width: 2,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F4C5C).withOpacity(0.3),
            blurRadius: 12,
            spreadRadius: 2,
          ),
        ],
      ),
      child: Image.network(
        'https://openweathermap.org/img/wn/$iconCode@2x.png',
        width: size,
        height: size,
        errorBuilder: (context, error, stackTrace) =>
            Icon(Icons.cloud, color: Colors.grey, size: size),
      ),
    );
  }

  String _getTimeOfDay() {
    final hour = DateTime.now().hour;
    if (hour < 12) return "Good Morning 🌅";
    if (hour < 17) return "Good Afternoon ☀️";
    return "Good Evening 🌆";
  }

  String _getTravelAdvice(double temp, String condition, double windSpeed, int humidity) {
    bool isSafe = true;
    List<String> warnings = [];

    if (temp > 40) {
      isSafe = false;
      warnings.add("Extreme heat (${temp.round()}°C)");
    } else if (temp < -5) {
      isSafe = false;
      warnings.add("Freezing temperature (${temp.round()}°C)");
    } else if (temp > 35) {
      warnings.add("Very hot (${temp.round()}°C)");
    } else if (temp < 0) {
      warnings.add("Freezing cold (${temp.round()}°C)");
    }

    if (condition.toLowerCase().contains('thunderstorm')) {
      isSafe = false;
      warnings.add("Thunderstorm");
    } else if (condition.toLowerCase().contains('heavy rain')) {
      isSafe = false;
      warnings.add("Heavy rain");
    } else if (condition.toLowerCase().contains('snow')) {
      warnings.add("Snowy conditions");
    } else if (condition.toLowerCase().contains('fog') || condition.toLowerCase().contains('mist')) {
      warnings.add("Low visibility (fog/mist)");
    } else if (condition.toLowerCase().contains('rain')) {
      warnings.add("Rainy");
    }

    if (windSpeed > 20) {
      isSafe = false;
      warnings.add("High wind (${windSpeed.round()} m/s)");
    } else if (windSpeed > 12) {
      warnings.add("Strong wind (${windSpeed.round()} m/s)");
    }

    if (humidity > 85) {
      warnings.add("High humidity (${humidity}%)");
    }

    if (isSafe && warnings.isEmpty) {
      return "✅ Safe to travel";
    } else if (!isSafe) {
      return "⚠️ NOT SAFE to travel\n• ${warnings.join('\n• ')}";
    } else {
      return "⚠️ Travel with caution\n• ${warnings.join('\n• ')}";
    }
  }

  Color _getTravelColor(String advice) {
    if (advice.contains("✅")) return Colors.green;
    if (advice.contains("⚠️ NOT SAFE")) return Colors.red;
    return Colors.orange;
  }

  Color _getTravelBgColor(String advice) {
    if (advice.contains("✅")) return Colors.green.withOpacity(0.15);
    if (advice.contains("⚠️ NOT SAFE")) return Colors.red.withOpacity(0.15);
    return Colors.orange.withOpacity(0.15);
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF0F4C5C), Color(0xFF1A6B7A)],
          ),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white.withOpacity(0.1), width: 1),
        ),
        child: const Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
            ),
            SizedBox(height: 12),
            Text("Fetching weather...", style: TextStyle(color: Colors.white70)),
          ],
        ),
      );
    }

    if (_error.isNotEmpty) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF0F4C5C), Color(0xFF1A6B7A)],
          ),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white.withOpacity(0.1), width: 1),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error, color: Colors.red, size: 40),
            const SizedBox(height: 12),
            Text(_error, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white70)),
            const SizedBox(height: 12),
            TextButton(
              onPressed: _fetchWeather,
              child: const Text('Retry', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      );
    }

    if (_weatherData == null) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF0F4C5C), Color(0xFF1A6B7A)],
          ),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white.withOpacity(0.1), width: 1),
        ),
        child: const Center(
          child: Text("Weather data not available", style: TextStyle(color: Colors.white70)),
        ),
      );
    }

    final weather = _weatherData!;

    if (widget.compact) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF0F4C5C), Color(0xFF1A6B7A)],
          ),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white.withOpacity(0.15), width: 1),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.network(
              'https://openweathermap.org/img/wn/${weather.iconCode}@2x.png',
              width: 28,
              height: 28,
              errorBuilder: (context, error, stackTrace) =>
                  const Icon(Icons.cloud, color: Colors.white, size: 28),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  "${weather.temperature.round()}°C",
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                ),
                Text(
                  weather.description,
                  style: const TextStyle(color: Colors.white70, fontSize: 10),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ],
        ),
      );
    }

    final travelAdvice = _getTravelAdvice(
      weather.temperature,
      weather.mainCondition,
      weather.windSpeed,
      weather.humidity,
    );
    final travelColor = _getTravelColor(travelAdvice);
    final travelBgColor = _getTravelBgColor(travelAdvice);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF0F4C5C), Color(0xFF1A6B7A)],
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F4C5C).withOpacity(0.3),
            blurRadius: 20,
            offset: const Offset(0, 8),
            spreadRadius: 4,
          ),
        ],
        border: Border.all(color: Colors.white.withOpacity(0.1), width: 1),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  _getTimeOfDay(),
                  style: const TextStyle(color: Colors.white70, fontSize: 14, fontWeight: FontWeight.w500),
                ),
              ),
              Row(
                children: [
                  GestureDetector(
                    onTap: _fetchWeather,
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.1),
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white.withOpacity(0.2), width: 1),
                      ),
                      child: const Icon(Icons.refresh_rounded, color: Colors.white70, size: 20),
                    ),
                  ),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: () => Navigator.of(context).pop(),
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: Colors.red.withOpacity(0.15),
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.red.withOpacity(0.3), width: 1.5),
                      ),
                      child: const Icon(Icons.close_rounded, color: Colors.red, size: 22),
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),

          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _buildWeatherIcon(weather.iconCode, size: 55),
              const SizedBox(width: 16),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "${weather.temperature.round()}°C",
                    style: const TextStyle(color: Colors.white, fontSize: 36, fontWeight: FontWeight.bold),
                  ),
                  Text(
                    weather.description.toUpperCase(),
                    style: const TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w500, letterSpacing: 1),
                  ),
                  Text(
                    weather.location,
                    style: const TextStyle(color: Colors.white60, fontSize: 11),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Divider(color: Colors.white24),

          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: travelBgColor,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: travelColor.withOpacity(0.3), width: 1),
            ),
            child: Row(
              children: [
                Icon(
                  travelAdvice.contains("✅") ? Icons.check_circle : Icons.warning_amber_rounded,
                  color: travelColor,
                  size: 20,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    travelAdvice,
                    style: TextStyle(color: travelColor, fontSize: 13, fontWeight: FontWeight.w600, height: 1.4),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildWeatherDetail(Icons.thermostat, 'Feels like', "${weather.feelsLike.round()}°C", Colors.orange),
              _buildWeatherDetail(Icons.water_drop, 'Humidity', "${weather.humidity}%", Colors.blue),
              _buildWeatherDetail(Icons.air, 'Wind', "${weather.windSpeed} m/s", Colors.teal),
            ],
          ),
          const SizedBox(height: 8),

          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildWeatherDetail(Icons.compress, 'Pressure', "${weather.pressure} hPa", Colors.purple),
              _buildWeatherDetail(Icons.visibility, 'Visibility', "${(weather.visibility / 1000).toStringAsFixed(1)} km", Colors.lightBlue),
              _buildWeatherDetail(Icons.cloud, 'Clouds', "${weather.clouds}%", Colors.grey),
            ],
          ),
          const SizedBox(height: 8),

          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildTimeDetail(Icons.wb_twilight, 'Sunrise', weather.sunrise, Colors.orange),
              _buildTimeDetail(Icons.wb_twilight, 'Sunset', weather.sunset, Colors.deepOrange),
            ],
          ),
          const SizedBox(height: 6),

          Text(
            "Last updated: ${DateFormat('h:mm a').format(DateTime.now())}",
            style: const TextStyle(color: Colors.white38, fontSize: 10),
          ),
        ],
      ),
    );
  }

  Widget _buildWeatherDetail(IconData icon, String label, String value, Color color) {
    return Column(
      children: [
        Icon(icon, color: color, size: 18),
        const SizedBox(height: 2),
        Text(label, style: const TextStyle(color: Colors.white54, fontSize: 9)),
        Text(value, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
      ],
    );
  }

  Widget _buildTimeDetail(IconData icon, String label, String time, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: color, size: 14),
        const SizedBox(width: 4),
        Text(label, style: const TextStyle(color: Colors.white54, fontSize: 10)),
        const SizedBox(width: 6),
        Text(time, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 11)),
      ],
    );
  }
}

// ✅ EXTENDED WEATHER DATA CLASS
class WeatherData {
  final String location;
  final double temperature;
  final double feelsLike;
  final int humidity;
  final double windSpeed;
  final String description;
  final String mainCondition;
  final int pressure;
  final int visibility;
  final int clouds;
  final String sunrise;
  final String sunset;
  final String iconCode;

  WeatherData({
    required this.location,
    required this.temperature,
    required this.feelsLike,
    required this.humidity,
    required this.windSpeed,
    required this.description,
    required this.mainCondition,
    required this.pressure,
    required this.visibility,
    required this.clouds,
    required this.sunrise,
    required this.sunset,
    required this.iconCode,
  });

  factory WeatherData.fromJson(Map<String, dynamic> json) {
    final sunriseTime = DateTime.fromMillisecondsSinceEpoch(
      json['sys']['sunrise'] * 1000,
    );
    final sunsetTime = DateTime.fromMillisecondsSinceEpoch(
      json['sys']['sunset'] * 1000,
    );

    return WeatherData(
      location: json['name'] ?? 'Unknown',
      temperature: (json['main']['temp'] as num).toDouble(),
      feelsLike: (json['main']['feels_like'] as num).toDouble(),
      humidity: json['main']['humidity'] ?? 0,
      windSpeed: (json['wind']['speed'] as num).toDouble(),
      description: json['weather'][0]['description'] ?? 'N/A',
      mainCondition: json['weather'][0]['main'] ?? 'N/A',
      pressure: json['main']['pressure'] ?? 0,
      visibility: json['visibility'] ?? 10000,
      clouds: json['clouds']['all'] ?? 0,
      sunrise: DateFormat('h:mm a').format(sunriseTime),
      sunset: DateFormat('h:mm a').format(sunsetTime),
      iconCode: json['weather'][0]['icon'] ?? '01d',
    );
  }
}