from flask import Flask, render_template_string
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

        landing_bucket = storage_client.bucket(LANDING_ZONE_BUCKET)
        blob = landing_bucket.blob('sales.csv')
        csv_data = blob.download_as_text()
        df = pd.read_csv(io.StringIO(csv_data))

        sales_by_category = df.groupby('Categoria')['Valor'].sum().reset_index()
        report_data = sales_by_category.to_json(orient='records', indent=4)

        processed_bucket = storage_client.bucket(PROCESSED_ZONE_BUCKET)
        processed_blob = processed_bucket.blob('report.json')
        processed_blob.upload_from_string(report_data, content_type='application/json')

        final_report_blob = processed_bucket.blob('report.json')
        final_report_json = final_report_blob.download_as_text()
        final_report = json.loads(final_report_json)

        html_output = "<h1>Relatório de Vendas por Categoria</h1>"
        html_output += "<p>Dados processados e carregados no Google Cloud Storage.</p>"
        html_output += "<pre>" + json.dumps(final_report, indent=2) + "</pre>"
        html_output += "<h2>Pronto para o LinkedIn!</h2>"
        html_output += "<p>Copie o conteúdo abaixo para o seu post:</p>"
        linkedin_post = "📊 **Relatório de Vendas do Dia!** 📊\n\n"
        for item in final_report:
            linkedin_post += f"- Categoria: {item['Categoria']}, Total de Vendas: R$ {item['Valor']:.2f}\n"
        linkedin_post += "\n#ETL #DataAnalytics #GCP #Kubernetes #Python"
        html_output += "<textarea rows='10' cols='80'>" + linkedin_post + "</textarea>"

        return render_template_string(html_output)

    except Exception as e:
        return render_template_string(f"<h1>Erro na Aplicação ETL</h1><p>Ocorreu um erro: {e}</p><p>Verifique se os buckets existem e se o arquivo 'sales.csv' está na 'landing-zone'.</p>")

if __name__ == '__main__':
    app.run(debug=True, host='0.0.0.0', port=os.environ.get('PORT', 8080))