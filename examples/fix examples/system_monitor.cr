require "../src/hauyna-web-socket"
require "http/server"

# Sistema de monitoreo de recursos en tiempo real

class SystemMetric
  include JSON::Serializable

  property timestamp : Time
  property cpu_usage : Float64
  property memory_used : Int64
  property memory_total : Int64
  property disk_used : Int64
  property disk_total : Int64
  property network_rx : Int64
  property network_tx : Int64
  property processes : Array(ProcessInfo)

  def initialize
    @timestamp = Time.local
    @cpu_usage = get_cpu_usage
    @memory_used = get_memory_used
    @memory_total = get_memory_total
    @disk_used = get_disk_used
    @disk_total = get_disk_total
    @network_rx = get_network_rx
    @network_tx = get_network_tx
    @processes = get_top_processes
  end

  private def get_cpu_usage : Float64
    # Simulación de datos para el ejemplo
    rand * 100
  end

  private def get_memory_used : Int64
    # Simulación
    (rand * 16 * 1024 * 1024 * 1024).to_i64
  end

  private def get_memory_total : Int64
    (16_i64 * 1024_i64 * 1024_i64 * 1024_i64) # 16GB como Int64
  end

  private def get_disk_used : Int64
    # Simulación
    (rand * 512 * 1024 * 1024 * 1024).to_i64
  end

  private def get_disk_total : Int64
    (512_i64 * 1024_i64 * 1024_i64 * 1024_i64) # 512GB como Int64
  end

  private def get_network_rx : Int64
    # Simulación
    (rand * 1024 * 1024).to_i64
  end

  private def get_network_tx : Int64
    # Simulación
    (rand * 1024 * 1024).to_i64
  end

  private def get_top_processes : Array(ProcessInfo)
    # Simulación de procesos
    [
      ProcessInfo.new("chrome", rand * 20, rand * 2048),
      ProcessInfo.new("vscode", rand * 15, rand * 1024),
      ProcessInfo.new("postgres", rand * 10, rand * 512),
      ProcessInfo.new("nginx", rand * 5, rand * 256),
      ProcessInfo.new("crystal", rand * 8, rand * 512),
    ]
  end
end

class ProcessInfo
  include JSON::Serializable

  property name : String
  property cpu : Float64
  property memory : Float64

  def initialize(@name : String, @cpu : Float64, @memory : Float64)
  end
end

class Monitor
  property metrics : Array(SystemMetric)
  property alerts : Array(Alert)
  property users : Hash(String, String)

  MAX_METRICS = 60
  MAX_ALERTS  = 10

  def initialize
    @metrics = [] of SystemMetric
    @alerts = [] of Alert
    @users = {} of String => String
  end

  def add_user(id : String, name : String)
    @users[id] = name
  end

  def update_metrics
    metric = SystemMetric.new
    @metrics << metric

    # Mantener solo las últimas MAX_METRICS mediciones
    if @metrics.size > MAX_METRICS
      @metrics = @metrics[-MAX_METRICS..]
    end

    # Verificar alertas
    check_alerts(metric)

    metric
  end

  private def check_alerts(metric : SystemMetric)
    if metric.cpu_usage > 90
      @alerts << Alert.new("CPU", "Uso de CPU crítico: #{metric.cpu_usage.round(2)}%")
    end

    memory_percent = (metric.memory_used.to_f / metric.memory_total) * 100
    if memory_percent > 90
      @alerts << Alert.new("Memory", "Memoria crítica: #{memory_percent.round(2)}%")
    end

    # Mantener solo las últimas MAX_ALERTS alertas
    if @alerts.size > MAX_ALERTS
      @alerts = @alerts[-MAX_ALERTS..]
    end
  end
end

class Alert
  include JSON::Serializable

  property type : String
  property message : String
  property timestamp : Time

  def initialize(@type : String, @message : String)
    @timestamp = Time.local
  end
end

monitor = Monitor.new

server = HTTP::Server.new do |context|
  router = Hauyna::WebSocket::Router.new
  handler = Hauyna::WebSocket::Handler.new

  handler.extract_identifier = ->(socket : HTTP::WebSocket, params : Hash(String, JSON::Any)) {
    params["user_id"]?.try(&.as_s)
  }

  handler.on_open = ->(socket : HTTP::WebSocket, params : Hash(String, JSON::Any)) {
    if (user_id = params["user_id"]?.try(&.as_s)) && (name = params["name"]?.try(&.as_s))
      monitor.add_user(user_id, name)
      Hauyna::WebSocket::ConnectionManager.add_to_group(user_id, "monitors")

      socket.send({
        type:    "init",
        metrics: monitor.metrics[-60..] || monitor.metrics, # Usar || para manejar arrays pequeños
        alerts:  monitor.alerts[-10..] || monitor.alerts,
      }.to_json)
    end
  }

  # Actualizar métricas cada segundo
  spawn do
    loop do
      sleep 1.seconds

      metric = monitor.update_metrics

      Hauyna::WebSocket::Events.send_to_group("monitors", {
        type:   "metrics_update",
        metric: metric,
        alerts: monitor.alerts[-10..] || monitor.alerts,
      }.to_json)
    end
  end

  router.websocket("/monitor", handler)

  next if router.call(context)

  if context.request.path == "/"
    context.response.content_type = "text/html"
    context.response.print <<-HTML
      <!DOCTYPE html>
      <html>
        <head>
          <title>Monitor del Sistema</title>
          <script src="https://cdn.jsdelivr.net/npm/chart.js"></script>
          <style>
            .container {
              max-width: 1200px;
              margin: 0 auto;
              padding: 20px;
            }
            .metrics-grid {
              display: grid;
              grid-template-columns: repeat(2, 1fr);
              gap: 20px;
              margin: 20px 0;
            }
            .metric-card {
              background: #f5f5f5;
              padding: 20px;
              border-radius: 8px;
              box-shadow: 0 2px 4px rgba(0,0,0,0.1);
            }
            .chart-container {
              position: relative;
              height: 200px;
              margin: 20px 0;
            }
            .processes {
              margin-top: 20px;
            }
            .process {
              display: grid;
              grid-template-columns: 1fr repeat(2, 100px);
              padding: 10px;
              border-bottom: 1px solid #eee;
            }
            .alerts {
              margin-top: 20px;
            }
            .alert {
              padding: 10px;
              margin: 5px 0;
              border-radius: 4px;
              background: #ffebee;
              color: #c62828;
            }
          </style>
        </head>
        <body>
          <div class="container">
            <div id="join" style="text-align: center;">
              <h2>Monitor del Sistema</h2>
              <input type="text" id="name" placeholder="Tu nombre">
              <button onclick="joinMonitor()">Entrar</button>
            </div>
            
            <div id="dashboard" style="display: none;">
              <h1>Monitor del Sistema</h1>
              
              <div class="metrics-grid">
                <div class="metric-card">
                  <h3>CPU</h3>
                  <div class="chart-container">
                    <canvas id="cpuChart"></canvas>
                  </div>
                </div>
                
                <div class="metric-card">
                  <h3>Memoria</h3>
                  <div class="chart-container">
                    <canvas id="memoryChart"></canvas>
                  </div>
                </div>
                
                <div class="metric-card">
                  <h3>Disco</h3>
                  <div class="chart-container">
                    <canvas id="diskChart"></canvas>
                  </div>
                </div>
                
                <div class="metric-card">
                  <h3>Red</h3>
                  <div class="chart-container">
                    <canvas id="networkChart"></canvas>
                  </div>
                </div>
              </div>
              
              <div class="processes">
                <h2>Procesos</h2>
                <div class="process">
                  <div><strong>Nombre</strong></div>
                  <div><strong>CPU %</strong></div>
                  <div><strong>Memoria MB</strong></div>
                </div>
                <div id="processes"></div>
              </div>
              
              <div class="alerts">
                <h2>Alertas</h2>
                <div id="alerts"></div>
              </div>
            </div>
          </div>

          <script>
            const userId = Math.random().toString(36).substr(2, 9);
            let ws;
            let cpuChart, memoryChart, diskChart, networkChart;
            let metrics = [];
            const MAX_POINTS = 60;
            
            function formatBytes(bytes) {
              const units = ['B', 'KB', 'MB', 'GB', 'TB'];
              let size = bytes;
              let unit = 0;
              
              while (size >= 1024 && unit < units.length - 1) {
                size /= 1024;
                unit++;
              }
              
              return `${size.toFixed(2)} ${units[unit]}`;
            }
            
            function createChart(ctx, label) {
              return new Chart(ctx, {
                type: 'line',
                data: {
                  labels: [],
                  datasets: [{
                    label: label,
                    data: [],
                    borderColor: '#2196F3',
                    tension: 0.4
                  }]
                },
                options: {
                  responsive: true,
                  maintainAspectRatio: false,
                  scales: {
                    y: {
                      beginAtZero: true
                    }
                  },
                  animation: {
                    duration: 0 // Desactivar animaciones para mejor rendimiento
                  }
                }
              });
            }
            
            function updateCharts(metric) {
              const time = new Date(metric.timestamp).toLocaleTimeString();
              
              function updateChartData(chart, value) {
                // Agregar nuevo punto
                metrics.push({time, value});
                
                // Mantener solo los últimos MAX_POINTS
                if (metrics.length > MAX_POINTS) {
                  metrics = metrics.slice(-MAX_POINTS);
                }
                
                // Actualizar la gráfica con todos los puntos
                chart.data.labels = metrics.map(m => m.time);
                chart.data.datasets[0].data = metrics.map(m => m.value);
                
                chart.update('none');
              }
              
              // CPU
              updateChartData(cpuChart, metric.cpu_usage);
              
              // Memoria
              const memoryPercent = (metric.memory_used / metric.memory_total) * 100;
              updateChartData(memoryChart, memoryPercent);
              
              // Disco
              const diskPercent = (metric.disk_used / metric.disk_total) * 100;
              updateChartData(diskChart, diskPercent);
              
              // Red
              const networkMBps = metric.network_rx / (1024 * 1024);
              updateChartData(networkChart, networkMBps);
            }
            
            function updateProcesses(processes) {
              const processesDiv = document.getElementById('processes');
              processesDiv.innerHTML = processes
                .sort((a, b) => b.cpu - a.cpu)
                .map(process => `
                  <div class="process">
                    <div>${process.name}</div>
                    <div>${process.cpu.toFixed(1)}%</div>
                    <div>${process.memory.toFixed(0)} MB</div>
                  </div>
                `).join('');
            }
            
            function updateAlerts(alerts) {
              const alertsDiv = document.getElementById('alerts');
              alertsDiv.innerHTML = alerts.map(alert => `
                <div class="alert">
                  [${new Date(alert.timestamp).toLocaleTimeString()}]
                  ${alert.type}: ${alert.message}
                </div>
              `).join('');
            }
            
            function handleMessage(event) {
              const data = JSON.parse(event.data);
              
              switch(data.type) {
                case 'init':
                  // Reiniciar métricas
                  metrics = [];
                  
                  // Limpiar gráficas
                  [cpuChart, memoryChart, diskChart, networkChart].forEach(chart => {
                    chart.data.labels = [];
                    chart.data.datasets[0].data = [];
                    chart.update('none');
                  });
                  
                  // Inicializar con datos históricos
                  if (data.metrics && data.metrics.length > 0) {
                    data.metrics.forEach(updateCharts);
                  }
                  updateAlerts(data.alerts || []);
                  break;
                  
                case 'metrics_update':
                  if (data.metric) {
                    updateCharts(data.metric);
                    updateProcesses(data.metric.processes || []);
                  }
                  updateAlerts(data.alerts || []);
                  break;
              }
            }
            
            function joinMonitor() {
              const name = document.getElementById('name').value.trim();
              if (!name) return;
              
              document.getElementById('join').style.display = 'none';
              document.getElementById('dashboard').style.display = 'block';
              
              // Inicializar gráficos
              cpuChart = createChart(
                document.getElementById('cpuChart').getContext('2d'),
                'CPU %'
              );
              
              memoryChart = createChart(
                document.getElementById('memoryChart').getContext('2d'),
                'Memoria %'
              );
              
              diskChart = createChart(
                document.getElementById('diskChart').getContext('2d'),
                'Disco %'
              );
              
              networkChart = createChart(
                document.getElementById('networkChart').getContext('2d'),
                'Red MB/s'
              );
              
              ws = new WebSocket(
                `ws://localhost:8080/monitor?user_id=${userId}&name=${name}`
              );
              
              ws.onmessage = handleMessage;
            }
          </script>
        </body>
      </html>
    HTML
  end
end

puts "Servidor iniciado en http://localhost:8080"
server.listen("0.0.0.0", 8080)
