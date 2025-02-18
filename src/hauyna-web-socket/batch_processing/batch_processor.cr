require "log"

module Hauyna::WebSocket
  module BatchProcessing
    # Error personalizado para el procesador de lotes
    class BatchProcessorError < Exception
      getter type : String
      getter details : String

      def initialize(@type : String, @details : String)
        super("Error en el procesador: #{@type} - #{@details}")
      end
    end

    # Configuration for batch processing
    class Config
      property batch_size : Int32
      property interval : Float64
      property max_queue_size : Int32
      property on_batch_start : Proc(Int32, Nil)?
      property on_batch_complete : Proc(Int32, Int32, Nil)?
      property on_queue_full : Proc(Int32, Nil)?
      property on_error : Proc(BatchProcessorError, Nil)?
      property processor : Proc(JSON::Any, Nil)?

      def initialize(
        @batch_size = 50,
        @interval = 0.1,
        @max_queue_size = 10_000,
        @on_batch_start = nil,
        @on_batch_complete = nil,
        @on_queue_full = nil,
        @on_error = nil,
        @processor = nil
      )
      end
    end

    # Main batch processor class
    class Processor
      @operations_channel : ::Channel(JSON::Any)
      @control_channel : ::Channel(Symbol)
      @config : Config
      @process_callback : Proc(JSON::Any, Nil)?
      @processing_fiber : Fiber?
      @mutex : Mutex
      @queue_size : Int32
      @stopped : Bool

      def initialize(@config : Config)
        @operations_channel = ::Channel(JSON::Any).new(@config.max_queue_size)
        @control_channel = ::Channel(Symbol).new
        @process_callback = nil
        @mutex = Mutex.new
        @processing_fiber = nil
        @queue_size = 0
        @stopped = false
        
        # Solo iniciamos el proceso en background si realmente necesitamos procesar en lotes
        if @config.batch_size > 1
          start_processing
        end
      end

      def add(operation : JSON::Any, &block : JSON::Any -> _)
        return if @stopped

        @mutex.synchronize do
          @process_callback = block
        end

        # Si el tamaño del lote es 1, procesamos inmediatamente
        if @config.batch_size <= 1
          begin
            block.call(operation)
          rescue ex
            handle_error("procesamiento_inmediato", "Error procesando operación: #{ex.message}")
          end
          return
        end

        # Verificamos si la cola está llena
        if @queue_size >= @config.max_queue_size
          @config.on_queue_full.try &.call(@config.max_queue_size)
          handle_error("cola_llena", "La cola ha alcanzado su tamaño máximo: #{@config.max_queue_size}")
          return
        end

        # Intentamos agregar a la cola
        begin
          @mutex.synchronize { @queue_size += 1 }
          @operations_channel.send(operation)
        rescue ::Channel::ClosedError
          @mutex.synchronize { @queue_size -= 1 }
          handle_error("canal_cerrado", "No se puede agregar la operación - el procesador está cerrado")
        end
      end

      def stop
        return if @stopped
        @mutex.synchronize do
          @stopped = true
          @control_channel.send(:stop)
          @operations_channel.close
          @control_channel.close
        end
        # Esperamos un poco para que el fiber termine
        sleep(Time::Span.new(nanoseconds: 100_000_000)) # 0.1 segundos
      end

      private def start_processing
        @processing_fiber = spawn do
          process_loop
        end
      end

      private def process_loop
        batch = [] of JSON::Any
        last_process_time = Time.monotonic

        loop do
          break if @stopped

          select
          when op = @operations_channel.receive
            @mutex.synchronize { @queue_size -= 1 }
            batch << op
            
            # Procesamos si alcanzamos el tamaño del lote
            if batch.size >= @config.batch_size
              process_batch(batch)
              batch.clear
              last_process_time = Time.monotonic
            end
          when @control_channel.receive
            # Procesamos el último lote antes de salir
            process_batch(batch) unless batch.empty?
            break
          else
            # Si ha pasado el intervalo y tenemos operaciones pendientes
            if !batch.empty? && (Time.monotonic - last_process_time) >= @config.interval.seconds
              process_batch(batch)
              batch.clear
              last_process_time = Time.monotonic
            end
            sleep(Time::Span.new(nanoseconds: 10_000_000)) # 0.01 segundos
          end
        end
      end

      private def process_batch(batch : Array(JSON::Any))
        return if batch.empty?
        
        @config.on_batch_start.try &.call(batch.size)
        errors = 0
        
        if callback = @mutex.synchronize { @process_callback }
          batch.each do |operation|
            begin
              callback.call(operation)
            rescue ex
              errors += 1
              handle_error("procesamiento_lote", "Error procesando operación: #{ex.message}")
            end
          end
        end
        
        @config.on_batch_complete.try &.call(batch.size, errors)
      end

      private def handle_error(type : String, details : String)
        error = BatchProcessorError.new(type, details)
        Log.error { error.message }
        @config.on_error.try &.call(error)
      end
    end
  end
end 