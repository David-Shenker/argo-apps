"""
Report Generator DAG
Generates daily business reports and stores them
"""
from datetime import datetime, timedelta
from airflow import DAG
from airflow.operators.python import PythonOperator
from airflow.operators.bash import BashOperator
from airflow.utils.task_group import TaskGroup

default_args = {
    'owner': 'analytics-team',
    'depends_on_past': False,
    'email_on_failure': False,
    'retries': 3,
    'retry_delay': timedelta(minutes=10),
}

def fetch_sales_data(**context):
    """Fetch sales metrics"""
    print("Fetching sales data...")
    data = {
        'total_sales': 150000,
        'transactions': 1250,
        'avg_order_value': 120,
        'date': context['ds']
    }
    context['ti'].xcom_push(key='sales_data', value=data)
    return data

def fetch_user_data(**context):
    """Fetch user activity metrics"""
    print("Fetching user activity data...")
    data = {
        'active_users': 5420,
        'new_signups': 145,
        'churn_rate': 2.3,
        'date': context['ds']
    }
    context['ti'].xcom_push(key='user_data', value=data)
    return data

def fetch_performance_data(**context):
    """Fetch system performance metrics"""
    print("Fetching performance data...")
    data = {
        'avg_response_time_ms': 145,
        'error_rate': 0.02,
        'uptime_percent': 99.95,
        'date': context['ds']
    }
    context['ti'].xcom_push(key='performance_data', value=data)
    return data

def generate_report(**context):
    """Compile all data into report"""
    ti = context['ti']
    sales = ti.xcom_pull(key='sales_data', task_ids='data_collection.fetch_sales')
    users = ti.xcom_pull(key='user_data', task_ids='data_collection.fetch_users')
    perf = ti.xcom_pull(key='performance_data', task_ids='data_collection.fetch_performance')

    report = {
        'report_date': context['ds'],
        'generated_at': str(datetime.now()),
        'sales_summary': sales,
        'user_summary': users,
        'performance_summary': perf,
    }

    print("=" * 50)
    print(f"DAILY REPORT - {context['ds']}")
    print("=" * 50)
    print(f"Sales: ${sales['total_sales']:,} ({sales['transactions']} transactions)")
    print(f"Users: {users['active_users']:,} active, {users['new_signups']} new")
    print(f"Performance: {perf['avg_response_time_ms']}ms avg, {perf['uptime_percent']}% uptime")
    print("=" * 50)

    context['ti'].xcom_push(key='report', value=report)
    return report

def store_report(**context):
    """Store report to persistent storage"""
    ti = context['ti']
    report = ti.xcom_pull(key='report', task_ids='generate_report')
    print(f"Storing report for {report['report_date']}...")
    return {"status": "stored", "location": f"/reports/{report['report_date']}.json"}

def notify_stakeholders(**context):
    """Send notification about report availability"""
    print("Notifying stakeholders that daily report is ready...")
    return {"notified": True, "channels": ["email", "slack"]}

with DAG(
    'report_generator',
    default_args=default_args,
    description='Daily business report generator',
    schedule_interval='0 6 * * *',  # Every day at 6 AM
    start_date=datetime(2024, 1, 1),
    catchup=False,
    tags=['reports', 'analytics', 'daily'],
) as dag:

    start = BashOperator(
        task_id='start',
        bash_command='echo "Starting daily report generation for {{ ds }}"',
    )

    with TaskGroup('data_collection') as data_collection:
        fetch_sales = PythonOperator(
            task_id='fetch_sales',
            python_callable=fetch_sales_data,
        )

        fetch_users = PythonOperator(
            task_id='fetch_users',
            python_callable=fetch_user_data,
        )

        fetch_performance = PythonOperator(
            task_id='fetch_performance',
            python_callable=fetch_performance_data,
        )

    generate = PythonOperator(
        task_id='generate_report',
        python_callable=generate_report,
    )

    store = PythonOperator(
        task_id='store_report',
        python_callable=store_report,
    )

    notify = PythonOperator(
        task_id='notify_stakeholders',
        python_callable=notify_stakeholders,
    )

    end = BashOperator(
        task_id='end',
        bash_command='echo "Daily report generation completed at $(date)"',
    )

    start >> data_collection >> generate >> store >> notify >> end

