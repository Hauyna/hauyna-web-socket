require "../src/hauyna-web-socket"

# Configuración simple
config = Hauyna::WebSocket::BatchConfig.new(
  batch_size: 2,  # Procesar dos a la vez
  interval: 0.5,  # Cada medio segundo
  max_queue_size: 5,
  on_batch_start: ->(size : Int32) {
    puts "\nIniciando lote de #{size} números..."
  },
  on_batch_complete: ->(size : Int32, errors : Int32) {
    puts "Lote completado: #{size} números procesados"
  }
)

# Creamos el procesador
processor = Hauyna::WebSocket::BatchProcessor.new(config)

# Números a procesar
numbers = [1, 2, 3, 4, 5]

puts "\nProcesando números..."
puts "-" * 30

# Procesamos cada número
numbers.each do |n|
  data = {"number" => n}.to_json
  json = JSON.parse(data)
  
  processor.add(json) do |item|
    number = item["number"].as_i
    result = number + 1
    puts "  #{number} + 1 = #{result}"
  end
  
  # Pequeña pausa entre números
  sleep(Time::Span.new(nanoseconds: 100_000_000)) # 100ms
end

# Esperamos que termine el procesamiento
sleep(Time::Span.new(seconds: 2))

# Detenemos el procesador
processor.stop

puts "-" * 30
puts "Proceso completado." 