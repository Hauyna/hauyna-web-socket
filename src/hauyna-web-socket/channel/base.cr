module Hauyna
  module WebSocket
    # Configuración dinámica de limpieza
    class CleanupConfig
      property batch_size : Int32
      property queue_size : Int32
      property interval : Float64
      property max_retries : Int32

      def initialize(
        @batch_size = 50,    # Número máximo de canales a procesar por lote
        @queue_size = 1000,  # Tamaño máximo de la cola de limpieza
        @interval = 0.1,     # Intervalo entre procesamiento de lotes (segundos)
        @max_retries = 3     # Máximo número de reintentos por operación
      )
      end
    end

    class Channel
      # Instancia de configuración
      @@cleanup_config = CleanupConfig.new

      # Método para actualizar la configuración
      def self.configure_cleanup(config : CleanupConfig)
        @@cleanup_config = config
      end

      # Método para obtener la configuración actual
      def self.cleanup_config
        @@cleanup_config
      end

      # Lock-free queue para operaciones
      private class LockFreeQueue(T)
        @head : Atomic(Node(T)?)
        @tail : Atomic(Node(T)?)

        private class Node(T)
          property next : Atomic(Node(T)?)
          property value : T

          def initialize(@value : T)
            @next = Atomic(Node(T)?).new(nil)
          end
        end

        def initialize
          @head = Atomic(Node(T)?).new(nil)
          @tail = Atomic(Node(T)?).new(nil)
        end

        def push(value : T)
          node = Node.new(value)
          loop do
            tail = @tail.get
            if tail.nil?
              if @head.compare_and_set(nil, node)
                @tail.set(node)
                break
              end
            else
              next_tail = tail.next.get
              if next_tail.nil?
                if tail.next.compare_and_set(nil, node)
                  @tail.compare_and_set(tail, node)
                  break
                end
              else
                @tail.compare_and_set(tail, next_tail)
              end
            end
          end
        end

        def pop? : T?
          loop do
            head = @head.get
            return nil if head.nil?
            next_head = head.next.get
            if @head.compare_and_set(head, next_head)
              if next_head.nil?
                @tail.compare_and_set(head, nil)
              end
              return head.value
            end
          end
        end

        def empty? : Bool
          @head.get.nil?
        end
      end

      # Optimización de locks con RWLock
      private class OptimizedLock
        @readers : Atomic(Int32)
        @writer_waiting : Atomic(Bool)
        @mutex : Mutex

        def initialize
          @readers = Atomic(Int32).new(0)
          @writer_waiting = Atomic(Bool).new(false)
          @mutex = Mutex.new
        end

        def read
          while @writer_waiting.get
            Fiber.yield
          end
          @readers.add(1)
          begin
            yield
          ensure
            @readers.sub(1)
          end
        end

        def write
          @writer_waiting.set(true)
          @mutex.synchronize do
            while @readers.get > 0
              Fiber.yield
            end
            yield
          ensure
            @writer_waiting.set(false)
          end
        end
      end

      # Reemplazar colas y locks tradicionales con versiones optimizadas
      @@cleanup_queue = LockFreeQueue(CleanupOperation).new
      @@channels_lock = OptimizedLock.new
      @@metrics_lock = OptimizedLock.new

      # Métricas de limpieza con acceso optimizado
      private class AtomicMetrics
        property processed_count : Atomic(Int64)
        property error_count : Atomic(Int64)
        property queue_size : Atomic(Int64)
        @process_time_sum : Atomic(Int64) # Almacenamos los microsegundos
        @process_time_mutex : Mutex

        def initialize
          @processed_count = Atomic(Int64).new(0)
          @error_count = Atomic(Int64).new(0)
          @queue_size = Atomic(Int64).new(0)
          @process_time_sum = Atomic(Int64).new(0)
          @process_time_mutex = Mutex.new
        end

        def add_process_time(seconds : Float64)
          microseconds = (seconds * 1_000_000).to_i64
          @process_time_sum.add(microseconds)
        end

        def avg_process_time : Float64
          count = @processed_count.get
          return 0.0 if count == 0
          
          @process_time_mutex.synchronize do
            total_microseconds = @process_time_sum.get
            (total_microseconds.to_f64 / count.to_f64) / 1_000_000
          end
        end
      end

      @@metrics = AtomicMetrics.new

      # Operación específica para cleanup con reintentos
      private class CleanupOperation
        getter socket : HTTP::WebSocket
        property retries : Int32 = 0
        property channels_pending : Set(String)? = nil

        def initialize(@socket)
        end

        def increment_retry
          @retries += 1
        end

        def max_retries_reached?
          @retries >= @@cleanup_config.max_retries
        end
      end

      @@channels = {} of String => Set(Subscription)
      @@operation_channel = ::Channel(ChannelOperation | CleanupOperation).new
      @@mutex = Mutex.new

      # Iniciar el procesador de operaciones
      spawn do
        loop do
          operation = @@operation_channel.receive
          case operation
          when ChannelOperation
            process_operation(operation)
          when CleanupOperation
            process_cleanup(operation)
          end
        end
      end

      # Método para limpiar todo el estado (usado en pruebas)
      def self.cleanup_all
        @@mutex.synchronize do
          @@channels.clear
        end
      end

      private def self.process_operation(operation : ChannelOperation)
        @@mutex.synchronize do
          case operation.type
          when :subscribe
            data = operation.data.as(ChannelOperation::SubscribeData)
            internal_subscribe(data[:channel], data[:socket], data[:identifier], data[:metadata])
          when :unsubscribe
            data = operation.data.as(ChannelOperation::UnsubscribeData)
            internal_unsubscribe(data[:channel], data[:socket])
          when :broadcast
            data = operation.data.as(ChannelOperation::BroadcastData)
            internal_broadcast(data[:channel], data[:message])
          end
        end
      rescue ex
        puts "ERROR procesando operación: #{ex.message}"
        puts ex.backtrace.join("\n")
      end

      private def self.process_cleanup(operation : CleanupOperation)
        @@mutex.synchronize do
          # Limpiar directamente todas las suscripciones del socket
          @@channels.each do |channel, subs|
            # Crear un nuevo set sin las suscripciones del socket
            new_subs = Set.new(subs.reject { |s| s.socket == operation.socket })
            if new_subs.empty?
              @@channels.delete(channel)
            else
              @@channels[channel] = new_subs
            end
          end
        end
      end

      # API pública
      def self.subscribe(channel : String, socket : HTTP::WebSocket, identifier : String, metadata = {} of String => JSON::Any)
        # Verificar que el socket esté registrado
        return unless ConnectionManager.get_identifier(socket)

        data = {
          channel:    channel,
          socket:     socket,
          identifier: identifier,
          metadata:   metadata,
        }
        @@operation_channel.send(
          ChannelOperation.new(:subscribe, data.as(ChannelOperation::SubscribeData))
        )
      end

      def self.unsubscribe(channel : String, socket : HTTP::WebSocket)
        data = {
          channel: channel,
          socket:  socket,
        }
        @@operation_channel.send(
          ChannelOperation.new(:unsubscribe, data.as(ChannelOperation::UnsubscribeData))
        )
      end

      def self.broadcast_to(channel : String, message : Hash(String, JSON::Any) | String)
        data = {
          channel: channel,
          message: message,
        }
        @@operation_channel.send(
          ChannelOperation.new(:broadcast, data.as(ChannelOperation::BroadcastData))
        )
      end

      # Métodos de consulta
      def self.subscription_count(channel : String) : Int32
        @@mutex.synchronize do
          @@channels[channel]?.try(&.size) || 0
        end
      end

      def self.subscribers(channel : String) : Array(String)
        @@mutex.synchronize do
          @@channels[channel]?.try(&.map(&.identifier).to_a) || [] of String
        end
      end

      def self.subscribed?(channel : String, socket : HTTP::WebSocket) : Bool
        @@mutex.synchronize do
          @@channels[channel]?.try(&.any? { |s| s.socket == socket }) || false
        end
      end

      def self.get_subscription_metadata(channel : String, socket : HTTP::WebSocket) : Hash(String, JSON::Any)?
        @@mutex.synchronize do
          @@channels[channel]?.try(&.find { |s| s.socket == socket }).try(&.metadata)
        end
      end

      def self.presence_data(channel : String) : Hash(String, JSON::Any)
        puts "DEBUG: Obteniendo datos de presencia para canal: #{channel}"

        # Obtener datos de presencia filtrados por canal
        presence_data = Presence.list_by_channel(channel)
        puts "DEBUG: Datos de presencia raw: #{presence_data.inspect}"

        # Formatear los datos para la respuesta
        formatted_data = {} of String => JSON::Any
        presence_data.each do |identifier, data|
          metadata = data["metadata"]?.try(&.as_h) || {} of String => JSON::Any
          state = data["state"]?.try(&.as_s) || metadata["state"]?.try(&.as_s) || "online"

          formatted_data[identifier] = JSON::Any.new({
            "user_id"      => JSON::Any.new(identifier),
            "metadata"     => JSON::Any.new(metadata.to_json),
            "state"        => JSON::Any.new(state),
            "connected_at" => metadata["joined_at"]?.try(&.as_s) || Time.local.to_unix_ms.to_s,
          }.to_json)
        end

        puts "DEBUG: Datos de presencia formateados: #{formatted_data.inspect}"
        formatted_data
      end

      def self.update_presence(socket : HTTP::WebSocket, state : ConnectionManager::ConnectionState)
        if identifier = ConnectionManager.get_identifier(socket)
          subscribed_channels(socket).each do |channel|
            presence_metadata = {
              "state"      => JSON::Any.new(case state
                when .error?
                  "error"
                when .disconnected?
                  "offline"
                else
                  state.to_s.downcase
                end),
              "channel"    => JSON::Any.new(channel),
              "updated_at" => JSON::Any.new(Time.local.to_unix_ms.to_s),
            }

            Presence.update(identifier, presence_metadata)
            puts "DEBUG: Presencia actualizada para #{identifier} en canal #{channel} - Estado: #{state}"
          end
        end
      end

      def self.subscribed_channels(socket : HTTP::WebSocket) : Array(String)
        @@mutex.synchronize do
          channels = [] of String
          @@channels.each do |channel, subs|
            if subs.any? { |s| s.socket == socket }
              channels << channel
            end
          end
          channels
        end
      end

      # Método público mejorado para cleanup
      def self.cleanup_socket(socket : HTTP::WebSocket)
        enqueue_cleanup(socket)
        ensure_cleanup_processor_running
      end

      # Encolar operación de limpieza usando lock-free queue
      private def self.enqueue_cleanup(socket : HTTP::WebSocket)
        operation = CleanupOperation.new(socket)
        @@cleanup_queue.push(operation)
        update_metric(:queue_size, 1)
      end

      # Asegurar que el procesador está corriendo
      private def self.ensure_cleanup_processor_running
        @@cleanup_mutex.synchronize do
          unless @@cleanup_running
            @@cleanup_running = true
            spawn do
              process_cleanup_queue
            end
          end
        end
      end

      # Procesador principal de la cola de limpieza
      private def self.process_cleanup_queue
        loop do
          batch = get_next_batch

          if batch.empty?
            @@cleanup_mutex.synchronize { @@cleanup_running = false }
            break
          end

          process_cleanup_batch(batch)
          sleep @@cleanup_config.interval
        end
      end

      # Obtener siguiente lote de operaciones
      private def self.get_next_batch
        @@cleanup_mutex.synchronize do
          batch = [] of CleanupOperation
          while batch.size < @@cleanup_config.batch_size && !@@cleanup_queue.empty?
            batch << @@cleanup_queue.pop
          end
          update_metric(:queue_size, @@cleanup_queue.empty? ? 0 : @@cleanup_queue.size)
          batch
        end
      end

      # Procesar un lote de operaciones de limpieza
      private def self.process_cleanup_batch(batch : Array(CleanupOperation))
        batch.each do |operation|
          start_time = Time.monotonic
          
          begin
            if operation.channels_pending.nil?
              @@channels_lock.read do
                channels_to_process = identify_channels_to_cleanup(operation.socket)
                operation.channels_pending = channels_to_process
              end
            end

            cleanup_channels(operation)
            
            process_time = Time.monotonic - start_time
            update_metric(:processed_count, 1)
            update_metric(:avg_process_time, process_time.total_seconds)
          rescue ex
            handle_cleanup_error(operation, ex)
          end
        end
      end

      # Identificar canales que necesitan limpieza
      private def self.identify_channels_to_cleanup(socket : HTTP::WebSocket) : Set(String)
        @@mutex.synchronize do
          @@channels.keys.select do |channel|
            @@channels[channel].any? { |s| s.socket == socket }
          end.to_set
        end
      end

      # Limpiar canales para una operación
      private def self.cleanup_channels(operation : CleanupOperation)
        return unless pending = operation.channels_pending

        pending.each do |channel|
          @@mutex.synchronize do
            if subs = @@channels[channel]?
              new_subs = Set.new(subs.reject { |s| s.socket == operation.socket })
              if new_subs.empty?
                @@channels.delete(channel)
              else
                @@channels[channel] = new_subs
              end
            end
          end
          pending.delete(channel)
        end
      end

      # Manejar errores durante la limpieza
      private def self.handle_cleanup_error(operation : CleanupOperation, error : Exception)
        update_metric(:error_count, 1)
        Log.error { "Error durante limpieza: #{error.message}" }
        
        if !operation.max_retries_reached?
          operation.increment_retry
          @@cleanup_mutex.synchronize do
            @@cleanup_queue.push(operation)
          end
        else
          Log.error { "Máximo de reintentos alcanzado para socket: #{operation.socket.object_id}" }
        end
      end

      # Actualizar métricas de forma atómica
      private def self.update_metric(metric : Symbol, value : Int32 | Int64 | Float64)
        case metric
        when :processed_count
          @@metrics.processed_count.add(value.to_i64)
        when :error_count
          @@metrics.error_count.add(value.to_i64)
        when :queue_size
          @@metrics.queue_size.set(value.to_i64)
        when :avg_process_time
          @@metrics.add_process_time(value.to_f64)
        end
      end

      # Obtener métricas de forma thread-safe
      def self.cleanup_metrics
        {
          processed_count:  @@metrics.processed_count.get,
          error_count:     @@metrics.error_count.get,
          queue_size:      @@metrics.queue_size.get,
          avg_process_time: @@metrics.avg_process_time,
        }
      end

      # Testing helpers para verificar concurrencia
      {% if flag?(:test) %}
        def self.testing_helper
          TestingHelper
        end

        private module TestingHelper
          extend self

          def simulate_concurrent_operations(count : Int32)
            operations = Array(Future(Nil)).new(count)
            count.times do
              operations << Future.new do
                yield
              end
            end
            operations.each(&.get)
          end
        end
      {% end %}
    end
  end
end
