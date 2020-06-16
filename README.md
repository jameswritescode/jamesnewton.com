# jamesnewton.com

This is my personal website & playground

## Development

### Setup

```
$ bundle
$ yarn
$ rails db:prepare gql
```

### Processes

1. Run `rails server` and `bin/webpack-dev-server` as separate processes
2. open http://localhost:3000

## Production

Automatic deployment via Heroku + GitHub

## Technologies

* Deployments via Heroku
* Error reporting via `rollbar`
* File uploads to S3 via `shrine`
* GraphQL via `graphql-ruby` with TypeScript type geneneration via `graphql-code-generator`
* Rails
* React with TypeScript via `ts-loader`
* Sitemap generation to S3 via `sitemap_generator`
