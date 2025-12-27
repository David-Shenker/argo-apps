"""
Data Pipeline DAG
Extracts data from source, transforms it, and loads to destination
"""
from datetime import datetime, timedelta
from airflow import DAG
from airflow.operators.python import PythonOperator
from airflow.operators.bash import BashOperator

default_args = {
    'owner': 'data-team',
    'depends_on_past': False,
    'email_on_failure': False,
    'email_on_retry': False,
    'retries': 2,
    'retry_delay': timedelta(minutes=5),
}

def extract_data(**context):
    """Extract data from source"""
    print("Extracting data from source system...")
    data = {"records": 1000, "source": "api", "timestamp": str(datetime.now())}
    context['ti'].xcom_push(key='extracted_data', value=data)
    return data

def transform_data(**context):
    """Transform extracted data"""
    ti = context['ti']
    data = ti.xcom_pull(key='extracted_data', task_ids='extract')
    print(f"Transforming {data['records']} records...")
    transformed = {
        **data,
        "transformed": True,
        "records_processed": data['records'],
    }
    ti.xcom_push(key='transformed_data', value=transformed)
    return transformed

def load_data(**context):
    """Load data to destination"""
    ti = context['ti']
    data = ti.xcom_pull(key='transformed_data', task_ids='transform')
    print(f"Loading {data['records_processed']} records to destination...")
    return {"status": "success", "loaded_records": data['records_processed']}

with DAG(
    'data_pipeline',
    default_args=default_args,
    description='ETL data pipeline for processing records',
    schedule_interval='0 */6 * * *',  # Every 6 hours
    start_date=datetime(2024, 1, 1),
    catchup=False,
    tags=['etl', 'data', 'pipeline'],
) as dag:

    extract = PythonOperator(
        task_id='extract',
        python_callable=extract_data,
    )

    transform = PythonOperator(
        task_id='transform',
        python_callable=transform_data,
    )

    load = PythonOperator(
        task_id='load',
        python_callable=load_data,
    )

    cleanup = BashOperator(
        task_id='cleanup',
        bash_command='echo "Pipeline completed successfully at $(date)"',
    )

    extract >> transform >> load >> cleanup

