#!/bin/bash
# Compatible with MS Windows + MSYS2
# Written by Andrea Giani

echo " Starting FPGA setup..."

# Remove existing FPGA folder if it exists
rm -rf fpga

# Create new FPGA and build folders
mkdir -p fpga/build

echo " Checking for FPGA tools..."
for tool in yosys nextpnr-ice40 nextpnr-generic nextpnr-ecp5 openFPGALoader ecpprog iceprog icepack icetime python python-pandas python-scikit-learn; do
    if command -v $tool &> /dev/null; then
        echo "$tool found!"
    else
        echo "$tool not found, installing..."
        pacman -S --needed --noconfirm mingw-w64-x86_64-$tool
    fi
done

# Update package manager only if necessary
echo " Updating package manager..."
pacman -Sy --noconfirm

echo " Installing required packages..."
for pkg in base-devel mingw-w64-x86_64-gcc mingw-w64-x86_64-cmake mingw-w64-x86_64-nextpnr mingw-w64-x86_64-openFPGALoader mingw-w64-x86_64-ecpprog mingw-w64-x86_64-icestorm mingw-w64-x86_64-yosys mingw-w64-x86_64-libusb mingw-w64-ucrt-x86_64-gcc; do
    if ! pacman -Q $pkg &> /dev/null; then
        pacman -S --needed --noconfirm $pkg
    fi
done

# SQLite Database
DB_FILE="fpga/fpga_data.db"

# Create SQLite DB and table (if not exists)
echo " Setting up SQLite Database..."
sqlite3 "$DB_FILE" <<EOF
CREATE TABLE IF NOT EXISTS synthesis_results (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    timestamp TEXT,
    freq_max REAL,
    cells INTEGER,
    timing_ns REAL
);
EOF

# Logging
LOG_FILE="fpga/log.txt"
echo " FPGA Setup Started - $(date)" > "$LOG_FILE"

while true; do
    # Menu interattivo
    echo "--------------------------------------"
    echo "Choose an option:"
    echo "1) FPGA tool verification"
    echo "2) Synthesize and generate bitstream"
    echo "3) Simulate RBF generation (Quartus)"
    echo "4) Check FPGA connection"
	echo "5) Analyze FPGA Data"
    echo "0) Exit"
    echo "--------------------------------------"
    read -p "Enter choice: " choice

    # Option 0: Exit script
    if [[ "$choice" == "0" ]]; then
        echo " Exiting FPGA setup..."
        exit 0
    fi

    # Option 1: FPGA tool verification
    if [[ "$choice" == "1" ]]; then
        echo " Checking for FPGA tools..." | tee -a "$LOG_FILE"
        for tool in yosys nextpnr-ice40 nextpnr-generic nextpnr-ecp5 openFPGALoader ecpprog iceprog icepack icetime python python-pandas python-scikit-learn; do
            if command -v $tool &> /dev/null; then
                echo "$tool found!" | tee -a "$LOG_FILE"
            else
                echo "$tool not found, installing..." | tee -a "$LOG_FILE"
                pacman -S --needed --noconfirm mingw-w64-x86_64-$tool | tee -a "$LOG_FILE"
            fi
        done
        echo " FPGA tool verification complete!" | tee -a "$LOG_FILE"
    fi

    # Option 2: Synthesize and collect metrics
    if [[ "$choice" == "2" ]]; then
        echo " Synthesis and bitstream generation..." | tee -a "$LOG_FILE"

		for i in {1..5}; do
			# Genera dimensione contatore variabile
			counter_bits=$((22 + i))
			reset_value=$((12000000 * i))

			# Generate Verilog file
			echo " Creating Verilog file #$i..." | tee -a "$LOG_FILE"
			cat <<EOF > fpga/blink.v
module blink (
    input wire clk,
    output reg led
);
    reg [$(($counter_bits-1)):0] counter = 0;

    always @(posedge clk) begin
        counter <= counter + 1;
        if (counter == $reset_value) begin
            led <= ~led;
            counter <= 0;
        end
    end
endmodule
EOF

        # Generate PCF file
        echo " Creating PCF file..." | tee -a "$LOG_FILE"
        cat <<EOF > fpga/board.pcf
set_io clk 21
set_io led 23
EOF

        # Run synthesis & collect metrics
        echo " Running Yosys synthesis..." | tee -a "$LOG_FILE"
        yosys -p "read_verilog fpga/blink.v; synth_ice40 -json fpga/build/blink.json" | tee -a "$LOG_FILE"

        # Run place-and-route
        echo " Running nextpnr synthesis..." | tee -a "$LOG_FILE"
        nextpnr-ice40 --json fpga/build/blink.json --pcf fpga/board.pcf --asc fpga/build/blink.asc --package tq144 | tee -a "$LOG_FILE"

        # Extract FPGA metrics (fake values for now)
    #   FREQ_MAX=12.00  # Example MHz
    #   CELLS_USED=$(grep -o "SB_LUT4" fpga/build/blink.json | wc -l)
    #   TIMING_NS=1.13  # Example nanoseconds
        FREQ_MAX=$((12 + i)) 
        CELLS_USED=$((50 + i*10))  
        TIMING_NS=$(echo "1.13 - $i*0.05" | bc)
		
        # Save metrics to SQLite DB
        echo " Saving FPGA synthesis metrics to DB..."
        sqlite3 "$DB_FILE" <<EOF
INSERT INTO synthesis_results (timestamp, freq_max, cells, timing_ns)
VALUES ('$(date)', $FREQ_MAX, $CELLS_USED, $TIMING_NS);
EOF

        echo " Metrics saved to SQLite database!" | tee -a "$LOG_FILE"

		done
    fi

    # Option 3: Simulate RBF generation (Quartus)
    if [[ "$choice" == "3" ]]; then
        echo " Simulating RBF generation (Quartus)..." | tee -a "$LOG_FILE"

        echo " Simulating Quartus conversion..." | tee -a "$LOG_FILE"
        touch fpga/build/fake.sof
        echo " Fake SOF file generated!" | tee -a "$LOG_FILE"

        echo " Simulating Quartus conversion to RBF..." | tee -a "$LOG_FILE"
        cp fpga/build/fake.sof fpga/build/fake.rbf
        echo " Fake RBF generated!" | tee -a "$LOG_FILE"
    fi

    # Option 4: Check FPGA connection
    if [[ "$choice" == "4" ]]; then
        echo " Checking for FPGA connection..." | tee -a "$LOG_FILE"

        OS_TYPE=$(uname -s)
        FPGA_CONNECTED=false

        if [[ "$OS_TYPE" == "Linux" ]]; then
            if lsusb | grep -q "0403:6010\|0403:6014"; then
                FPGA_CONNECTED=true
            fi
        elif [[ "$OS_TYPE" == "MINGW64_NT"* ]]; then
            if powershell -Command "Get-PnpDevice -PresentOnly | Where-Object { \$_.InstanceId -match 'USB\\VID_0403&PID_(6010|6014)' }" | grep -q "DeviceID"; then
                FPGA_CONNECTED=true
            fi
        fi

        if [[ "$FPGA_CONNECTED" == true ]]; then
            echo " FPGA detected!" | tee -a "$LOG_FILE"
        else
            echo " No FPGA detected! Skipping FPGA check." | tee -a "$LOG_FILE"
        fi
    fi

   # Option 5: Analyze FPGA data
    if [[ "$choice" == "5" ]]; then
        echo " Creating and launching Python analysis script..."

        # Crea script Python senza Flask
        cat <<'EOF' > analyze_fpga.py
import sqlite3
import json
import pandas as pd
import numpy as np
import sys

try:
    from sklearn.linear_model import LinearRegression
    sklearn_available = True
except ImportError:
    sklearn_available = False

# Connessione a SQLite
conn = sqlite3.connect("fpga/fpga_data.db")
cursor = conn.cursor()

# Recupero dei dati FPGA
cursor.execute("SELECT timestamp, freq_max, cells, timing_ns FROM synthesis_results ORDER BY id DESC LIMIT 100")
data = cursor.fetchall()
conn.close()

# Se non ci sono dati, generiamo dati demo
if not data:
    print(" No FPGA data found! Generating demo data...")
    data = []
    import random
    from datetime import datetime, timedelta
    
    base_time = datetime.now()
    for i in range(10):
        timestamp = (base_time - timedelta(minutes=i*10)).strftime("%Y-%m-%d %H:%M:%S")
        freq = random.uniform(10.0, 20.0)
        cells = random.randint(50, 200)
        timing = random.uniform(0.8, 1.5)
        data.append((timestamp, freq, cells, timing))

# Conversione in DataFrame Pandas
df = pd.DataFrame(data, columns=["timestamp", "freq_max", "cells", "timing_ns"])

# Inizializzazione dati AI
ai_data = {
    "predicted_freq": 0,
    "recommended_cells": 0,
    "recommended_timing": 0,
    "sklearn_available": sklearn_available
}

# Solo se sklearn è disponibile e ci sono abbastanza dati
if sklearn_available and len(data) > 2:
    try:
        # Rimuoviamo la colonna timestamp per l'addestramento
        df_no_timestamp = df.drop(columns=["timestamp"])

        # Modello AI: Previsione del miglior clock FPGA
        X = df_no_timestamp[["cells", "timing_ns"]]
        y = df_no_timestamp["freq_max"]

        # Addestramento modello
        model = LinearRegression()
        model.fit(X, y)

        # Previsione con la configurazione ideale FPGA
        best_cells = df["cells"].median()
        best_timing = df["timing_ns"].median()
        predicted_freq = model.predict([[best_cells, best_timing]])[0]

        # Aggiornamento dati AI
        ai_data.update({
            "predicted_freq": round(predicted_freq, 2),
            "recommended_cells": int(best_cells),
            "recommended_timing": round(best_timing, 2)
        })
    except Exception as e:
        ai_data["error"] = str(e)
        print(f" AI Error: {e}")

# Creazione del JSON combinato
combined_data = {
    "synthesis_results": df.to_dict(orient="records"),
    "ai_optimization": ai_data
}

# Salvataggio unico file JSON
with open("fpga/combined_data.json", "w") as f:
    json.dump(combined_data, f, indent=4)

print(" Combined data saved to fpga/combined_data.json")
EOF

        # Run Python script
        python3 analyze_fpga.py

        # Crea HTML senza chiamate Flask
        cat <<'EOF' > fpga/index.html
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <title>FPGA Synthesis & AI Optimization</title>
    <script src="https://cdn.jsdelivr.net/npm/chart.js"></script>
    <script>
        let chartInstance = null;

        async function loadData() {
            try {
                const response = await fetch("combined_data.json?t=" + new Date().getTime());
                const data = await response.json();

                renderData(data);
                renderChart(data.synthesis_results);
                
            } catch (error) {
                document.getElementById("results").innerHTML = `
                    <p class="error">Error loading data: ${error.message}</p>
                    <button onclick="loadData()">Retry</button>
                `;
            }
        }

        function renderData(data) {
            const fpgaData = data.synthesis_results;
            const aiData = data.ai_optimization;

            let content = `
                <h2>FPGA Synthesis Metrics</h2>
                <button onclick="loadData()">Refresh Data</button>
                <table border='1'>
                    <tr><th>Timestamp</th><th>Max Freq (MHz)</th><th>Cells</th><th>Timing (ns)</th></tr>
            `;
            
            fpgaData.forEach(row => {
                content += `<tr>
                    <td>${row.timestamp}</td>
                    <td>${row.freq_max.toFixed(2)}</td>
                    <td>${row.cells}</td>
                    <td>${row.timing_ns.toFixed(2)}</td>
                </tr>`;
            });
            
            content += "</table>";
            content += `<h2>AI Optimization</h2>`;
            
            if (aiData.sklearn_available) {
                content += `
                    <p>Recommended Max Frequency: <strong>${aiData.predicted_freq} MHz</strong></p>
                    <p>Suggested Cells: <strong>${aiData.recommended_cells}</strong></p>
                    <p>Predicted Timing: <strong>${aiData.recommended_timing} ns</strong></p>
                `;
            } else {
                content += `
                    <p class="error"> AI features disabled: scikit-learn not installed</p>
                    <p>Install with: <code>pacman -S mingw-w64-x86_64-python-scikit-learn</code></p>
                `;
            }

            if (aiData.error) {
                content += `<p class="error"> AI Error: ${aiData.error}</p>`;
            }

            document.getElementById("results").innerHTML = content;
        }

        function renderChart(fpgaData) {
            if (chartInstance) {
                chartInstance.destroy();
            }
            
            const labels = fpgaData.map(row => row.timestamp);
            const freqData = fpgaData.map(row => row.freq_max);
            const cellsData = fpgaData.map(row => row.cells);
            const timingData = fpgaData.map(row => row.timing_ns);

            const ctx = document.getElementById('fpgaChart').getContext('2d');
            chartInstance = new Chart(ctx, {
                type: 'line',
                data: {
                    labels: labels,
                    datasets: [
                        { 
                            label: "Max Frequency (MHz)", 
                            data: freqData, 
                            borderColor: "blue", 
                            fill: false 
                        },
                        { 
                            label: "Cells Used", 
                            data: cellsData, 
                            borderColor: "red", 
                            fill: false,
                            yAxisID: 'y1'
                        },
                        { 
                            label: "Timing (ns)", 
                            data: timingData, 
                            borderColor: "green", 
                            fill: false 
                        }
                    ]
                },
                options: {
                    responsive: true,
                    scales: {
                        y: {
                            beginAtZero: false,
                            title: { display: true, text: 'Freq/Timing' }
                        },
                        y1: {
                            beginAtZero: false,
                            position: 'right',
                            title: { display: true, text: 'Cells' },
                            grid: { drawOnChartArea: false }
                        }
                    }
                }
            });
        }
        
        window.onload = loadData;
    </script>
    <style>
        .error { color: red; font-weight: bold; }
        table { border-collapse: collapse; margin: 20px 0; width: 100%; }
        th, td { border: 1px solid #ddd; padding: 8px; text-align: center; }
        th { background-color: #f2f2f2; }
        button { padding: 10px; margin: 10px; background: #4CAF50; color: white; border: none; cursor: pointer; }
        button:hover { background: #45a049; }
    </style>
</head>
<body>
    <h1>FPGA Synthesis & AI Optimization</h1>
    <div id="results">Loading data...</div>
    <canvas id="fpgaChart" height="400"></canvas>
</body>
</html>
EOF

        echo " Web interface created!" | tee -a "$LOG_FILE"

        # Start web server with improved OS detection
        echo " Starting web server at http://localhost:8000"
        cd fpga

        # Improved Windows detection
        if [[ "$OSTYPE" == "msys" || "$OSTYPE" == "cygwin" || "$OSTYPE" == "win32" ]]; then
            echo " Run on Windows.."
            start http://localhost:8000/
            python -m http.server 8000
        else
            echo " Run on Linux/Unix.."
            python3 -m http.server 8000
        fi
    fi


done
