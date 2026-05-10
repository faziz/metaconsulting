# PostgreSQL Schema Setup Action

A reusable GitHub Action to create databases, users, and apply schemas on external PostgreSQL instances using Docker.

## Features

- ✅ Creates database users with secure passwords
- ✅ Creates databases with proper ownership
- ✅ Grants schema-level permissions automatically
- ✅ Installs PostgreSQL extensions
- ✅ Applies SQL schema files
- ✅ Uses Docker for consistent execution (no host dependencies)
- ✅ Fully configurable SSL modes

## Usage

### Basic

```yaml
- uses: metaconsulting/postgres-schema-setup@v1.1.0
  with:
    host: postgres.metaconsulting.au
    admin_user: ${{ secrets.POSTGRES_USER }}
    admin_password: ${{ secrets.DB_PASSWORD }}
    database: myapp_db
    db_user: myapp_user
    db_password: ${{ secrets.APP_DB_PASSWORD }}