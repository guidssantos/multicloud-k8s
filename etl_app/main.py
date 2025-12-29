from flask import Flask, render_template
from google.cloud import storage
import pandas as pd
import io
import os
import json

app = Flask(__name__)

LANDING_ZONE_BUCKET = os.environ.get('LANDING_ZONE_BUCKET')
PROCESSED_ZONE_BUCKET = os.environ.get('PROCESSED_ZONE_BUCKET')

@app.route('/')
def index():
    try:
        storage_client = storage.Client()

        # --- EXTRACT ---
        # Lê o CSV da landing zone
        landing_bucket = storage_client.bucket(LANDING_ZONE_BUCKET)
        blob = landing_bucket.blob('sales.csv')
        csv_data = blob.download_as_text()
        df = pd.read_csv(io.StringIO(csv_data))

        # --- TRANSFORM ---
        # Agrega vendas por categoria
        sales_by_category = df.groupby('Categoria')['Valor'].sum().reset_index()
        report_data = sales_by_category.to_json(orient='records', indent=4)

        # --- LOAD ---
        # Salva o relatório processado na processed zone
        processed_bucket = storage_client.bucket(PROCESSED_ZONE_BUCKET)
        processed_blob = processed_bucket.blob('report.json')
        processed_blob.upload_from_string(report_data, content_type='application/json')

        # Lê o relatório para exibir (demonstra que foi salvo e pode ser lido)
        final_report_blob = processed_bucket.blob('report.json')
        final_report_json = final_report_blob.download_as_text()
        final_report = json.loads(final_report_json)

        return render_template('index.html', report=final_report)

    except Exception as e:
        return render_template('index.html', error=f"Ocorreu um erro: {e}. Verifique se os buckets existem e se o arquivo 'sales.csv' está na 'landing-zone'.")

if __name__ == '__main__':
    app.run(debug=True, host='0.0.0.0', port=os.environ.get('PORT', 8080))