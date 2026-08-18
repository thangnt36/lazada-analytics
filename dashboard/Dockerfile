# Superset chính thức chưa hỗ trợ DuckDB sẵn — cài thêm duckdb-engine
# (SQLAlchemy dialect cho DuckDB) lên trên image gốc.
FROM apache/superset:latest

USER root
# Superset chay tu virtualenv rieng o /app/.venv, quan ly bang `uv` chu
# khong co pip rieng - phai cai dung target venv nay thi Superset moi
# thay duoc driver.
RUN uv pip install --python /app/.venv/bin/python duckdb duckdb-engine
USER superset
