# jamesnewton.com ![Testing](https://github.com/jameswritescode/jamesnewton.com/workflows/Testing/badge.svg)

This is my personal website & playground

## Development

### Setup

```
$ bundle
$ yarn
$ rails db:prepare gql
```

### Processes

1. Run `rails server` and `yarn server` as separate processes
2. open http://localhost:3000

### Tools

* Run `rails gql` when making changes to `.graphql` files or files in `app/graphql`
  * After making changes to `app/graphql` files this will update the `schema.{graphql,json}` files, which are used by ESLint, tests, and other tools
  * After making changes to queries inside of `.graphql` files and `gql` tags this will generate TypeScript types and typed methods based off of `schema.graphql` and the query for using in place of `@apollo/client` directly in most cases
* Use `[ci skip]` in commit message to skip running the testing workflow on GitHub

## Production

Automatic deployment via Heroku + GitHub

## Technologies

* Deployments via Heroku
* Error reporting via `rollbar`
* File uploads to S3 via `shrine`
* GraphQL via `graphql-ruby` with TypeScript type generation via `graphql-code-generator`
* Rails
* React with TypeScript via `ts-loader`
* Sitemap generation to S3 via `sitemap_generator`
