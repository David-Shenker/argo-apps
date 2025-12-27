"""
Health Check DAG
Monitors system health and sends alerts if issues detected
"""
from datetime import datetime, timedelta
from airflow import DAG
from airflow.operators.python import PythonOperator, BranchPythonOperator
from airflow.operators.bash import BashOperator
from airflow.operators.empty import EmptyOperator
import random

default_args = {
    'owner': 'platform-team',
    'depends_on_past': False,
    'email_on_failure': True,
    'retries': 1,
    'retry_delay': timedelta(minutes=2),
}

def check_api_health(**context):
    """Check API endpoint health"""
    status = random.choice(['healthy', 'healthy', 'healthy', 'degraded'])
    print(f"API Status: {status}")
    context['ti'].xcom_push(key='api_status', value=status)
    return status

def check_database_health(**context):
    """Check database connectivity"""
    status = random.choice(['healthy', 'healthy', 'healthy', 'unhealthy'])
    print(f"Database Status: {status}")
    context['ti'].xcom_push(key='db_status', value=status)
    return status

def check_cache_health(**context):
    """Check cache (Redis) health"""
    status = 'healthy'
    print(f"Cache Status: {status}")
    context['ti'].xcom_push(key='cache_status', value=status)
    return status

def evaluate_health(**context):
    """Evaluate overall system health and decide on action"""
    ti = context['ti']
    api_status = ti.xcom_pull(key='api_status', task_ids='check_api')
    db_status = ti.xcom_pull(key='db_status', task_ids='check_database')
    cache_status = ti.xcom_pull(key='cache_status', task_ids='check_cache')

    all_healthy = all(s == 'healthy' for s in [api_status, db_status, cache_status])

    if all_healthy:
        return 'all_healthy'
    else:
        return 'send_alert'

def send_alert(**context):
    """Send alert for unhealthy systems"""
    ti = context['ti']
    print("ALERT: System health check failed!")
    print(f"API: {ti.xcom_pull(key='api_status', task_ids='check_api')}")
    print(f"DB: {ti.xcom_pull(key='db_status', task_ids='check_database')}")
    print(f"Cache: {ti.xcom_pull(key='cache_status', task_ids='check_cache')}")

with DAG(
    'health_check',
    default_args=default_args,
    description='System health monitoring DAG',
    schedule_interval='*/15 * * * *',  # Every 15 minutes
    start_date=datetime(2024, 1, 1),
    catchup=False,
    tags=['monitoring', 'health', 'alerts'],
) as dag:

    check_api = PythonOperator(
        task_id='check_api',
        python_callable=check_api_health,
    )

    check_database = PythonOperator(
        task_id='check_database',
        python_callable=check_database_health,
    )

    check_cache = PythonOperator(
        task_id='check_cache',
        python_callable=check_cache_health,
    )

    evaluate = BranchPythonOperator(
        task_id='evaluate_health',
        python_callable=evaluate_health,
    )

    all_healthy = EmptyOperator(
        task_id='all_healthy',
    )

    alert = PythonOperator(
        task_id='send_alert',
        python_callable=send_alert,
    )

    complete = EmptyOperator(
        task_id='complete',
        trigger_rule='none_failed_min_one_success',
    )

    [check_api, check_database, check_cache] >> evaluate
    evaluate >> [all_healthy, alert] >> complete

