{% macro months_diff(start_col, end_col) %}
    {# Cross-dialect months_diff: works on both Trino and DuckDB #}
    {% if target.type == 'trino' %}
        date_diff('month', {{ start_col }}, {{ end_col }})
    {% elif target.type == 'duckdb' %}
        datediff('month', {{ start_col }}, {{ end_col }})
    {% else %}
        datediff('month', {{ start_col }}, {{ end_col }})
    {% endif %}
{% endmacro %}
