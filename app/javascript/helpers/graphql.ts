import gql from 'graphql-tag';
import * as ApolloReactCommon from '@apollo/react-common';
import * as ApolloReactHooks from '@apollo/react-hooks';
export type Maybe<T> = T | null;
export type Exact<T extends { [key: string]: any }> = { [K in keyof T]: T[K] };
/** All built-in and custom scalars, mapped to their actual values */
export type Scalars = {
  ID: string;
  String: string;
  Boolean: boolean;
  Int: number;
  Float: number;
};

/** Autogenerated input type of Login */
export type LoginInput = {
  /** A unique identifier for the client performing the mutation. */
  clientMutationId?: Maybe<Scalars['String']>;
  email: Scalars['String'];
  password: Scalars['String'];
};

/** Autogenerated return type of Login */
export type LoginPayload = {
  __typename?: 'LoginPayload';
  /** A unique identifier for the client performing the mutation. */
  clientMutationId?: Maybe<Scalars['String']>;
  success: Scalars['Boolean'];
};

export type Meta = {
  __typename?: 'Meta';
  description: Scalars['String'];
  title: Scalars['String'];
  type: Scalars['String'];
  url: Scalars['String'];
};

export type Mutation = {
  __typename?: 'Mutation';
  login: LoginPayload;
};


export type MutationLoginArgs = {
  input: LoginInput;
};

export type Post = {
  __typename?: 'Post';
  content: Scalars['String'];
  created: Scalars['String'];
  id: Scalars['ID'];
  meta: Meta;
  name: Scalars['String'];
  url: Scalars['String'];
};

export type Query = {
  __typename?: 'Query';
  latestTweet: Tweet;
  me?: Maybe<User>;
  post?: Maybe<Post>;
  posts: Array<Post>;
};


export type QueryPostArgs = {
  slug: Scalars['String'];
};

export type Tweet = {
  __typename?: 'Tweet';
  content: Scalars['String'];
  created: Scalars['String'];
};

export type User = {
  __typename?: 'User';
  id: Scalars['ID'];
};

export type PostQueryVariables = Exact<{
  slug: Scalars['String'];
}>;


export type PostQuery = (
  { __typename?: 'Query' }
  & { post?: Maybe<(
    { __typename?: 'Post' }
    & Pick<Post, 'id' | 'content' | 'created' | 'name'>
    & { meta: (
      { __typename?: 'Meta' }
      & Pick<Meta, 'description' | 'title' | 'type' | 'url'>
    ) }
  )> }
);

export type HomeQueryVariables = {};


export type HomeQuery = (
  { __typename?: 'Query' }
  & { latestTweet: (
    { __typename?: 'Tweet' }
    & Pick<Tweet, 'content' | 'created'>
  ), posts: Array<(
    { __typename?: 'Post' }
    & Pick<Post, 'id' | 'created' | 'name' | 'url'>
  )> }
);

export type MeQueryVariables = {};


export type MeQuery = (
  { __typename?: 'Query' }
  & { me?: Maybe<(
    { __typename?: 'User' }
    & Pick<User, 'id'>
  )> }
);

export type LoginMutationVariables = Exact<{
  input: LoginInput;
}>;


export type LoginMutation = (
  { __typename?: 'Mutation' }
  & { login: (
    { __typename?: 'LoginPayload' }
    & Pick<LoginPayload, 'success'>
  ) }
);


export const PostDocument = gql`
    query Post($slug: String!) {
  post(slug: $slug) {
    id
    content
    created
    name
    meta {
      description
      title
      type
      url
    }
  }
}
    `;

/**
 * __usePostQuery__
 *
 * To run a query within a React component, call `usePostQuery` and pass it any options that fit your needs.
 * When your component renders, `usePostQuery` returns an object from Apollo Client that contains loading, error, and data properties
 * you can use to render your UI.
 *
 * @param baseOptions options that will be passed into the query, supported options are listed on: https://www.apollographql.com/docs/react/api/react-hooks/#options;
 *
 * @example
 * const { data, loading, error } = usePostQuery({
 *   variables: {
 *      slug: // value for 'slug'
 *   },
 * });
 */
export function usePostQuery(baseOptions?: ApolloReactHooks.QueryHookOptions<PostQuery, PostQueryVariables>) {
        return ApolloReactHooks.useQuery<PostQuery, PostQueryVariables>(PostDocument, baseOptions);
      }
export function usePostLazyQuery(baseOptions?: ApolloReactHooks.LazyQueryHookOptions<PostQuery, PostQueryVariables>) {
          return ApolloReactHooks.useLazyQuery<PostQuery, PostQueryVariables>(PostDocument, baseOptions);
        }
export type PostQueryHookResult = ReturnType<typeof usePostQuery>;
export type PostLazyQueryHookResult = ReturnType<typeof usePostLazyQuery>;
export type PostQueryResult = ApolloReactCommon.QueryResult<PostQuery, PostQueryVariables>;
export const HomeDocument = gql`
    query Home {
  latestTweet {
    content
    created
  }
  posts {
    id
    created
    name
    url
  }
}
    `;

/**
 * __useHomeQuery__
 *
 * To run a query within a React component, call `useHomeQuery` and pass it any options that fit your needs.
 * When your component renders, `useHomeQuery` returns an object from Apollo Client that contains loading, error, and data properties
 * you can use to render your UI.
 *
 * @param baseOptions options that will be passed into the query, supported options are listed on: https://www.apollographql.com/docs/react/api/react-hooks/#options;
 *
 * @example
 * const { data, loading, error } = useHomeQuery({
 *   variables: {
 *   },
 * });
 */
export function useHomeQuery(baseOptions?: ApolloReactHooks.QueryHookOptions<HomeQuery, HomeQueryVariables>) {
        return ApolloReactHooks.useQuery<HomeQuery, HomeQueryVariables>(HomeDocument, baseOptions);
      }
export function useHomeLazyQuery(baseOptions?: ApolloReactHooks.LazyQueryHookOptions<HomeQuery, HomeQueryVariables>) {
          return ApolloReactHooks.useLazyQuery<HomeQuery, HomeQueryVariables>(HomeDocument, baseOptions);
        }
export type HomeQueryHookResult = ReturnType<typeof useHomeQuery>;
export type HomeLazyQueryHookResult = ReturnType<typeof useHomeLazyQuery>;
export type HomeQueryResult = ApolloReactCommon.QueryResult<HomeQuery, HomeQueryVariables>;
export const MeDocument = gql`
    query Me {
  me {
    id
  }
}
    `;

/**
 * __useMeQuery__
 *
 * To run a query within a React component, call `useMeQuery` and pass it any options that fit your needs.
 * When your component renders, `useMeQuery` returns an object from Apollo Client that contains loading, error, and data properties
 * you can use to render your UI.
 *
 * @param baseOptions options that will be passed into the query, supported options are listed on: https://www.apollographql.com/docs/react/api/react-hooks/#options;
 *
 * @example
 * const { data, loading, error } = useMeQuery({
 *   variables: {
 *   },
 * });
 */
export function useMeQuery(baseOptions?: ApolloReactHooks.QueryHookOptions<MeQuery, MeQueryVariables>) {
        return ApolloReactHooks.useQuery<MeQuery, MeQueryVariables>(MeDocument, baseOptions);
      }
export function useMeLazyQuery(baseOptions?: ApolloReactHooks.LazyQueryHookOptions<MeQuery, MeQueryVariables>) {
          return ApolloReactHooks.useLazyQuery<MeQuery, MeQueryVariables>(MeDocument, baseOptions);
        }
export type MeQueryHookResult = ReturnType<typeof useMeQuery>;
export type MeLazyQueryHookResult = ReturnType<typeof useMeLazyQuery>;
export type MeQueryResult = ApolloReactCommon.QueryResult<MeQuery, MeQueryVariables>;
export const LoginDocument = gql`
    mutation Login($input: LoginInput!) {
  login(input: $input) {
    success
  }
}
    `;
export type LoginMutationFn = ApolloReactCommon.MutationFunction<LoginMutation, LoginMutationVariables>;

/**
 * __useLoginMutation__
 *
 * To run a mutation, you first call `useLoginMutation` within a React component and pass it any options that fit your needs.
 * When your component renders, `useLoginMutation` returns a tuple that includes:
 * - A mutate function that you can call at any time to execute the mutation
 * - An object with fields that represent the current status of the mutation's execution
 *
 * @param baseOptions options that will be passed into the mutation, supported options are listed on: https://www.apollographql.com/docs/react/api/react-hooks/#options-2;
 *
 * @example
 * const [loginMutation, { data, loading, error }] = useLoginMutation({
 *   variables: {
 *      input: // value for 'input'
 *   },
 * });
 */
export function useLoginMutation(baseOptions?: ApolloReactHooks.MutationHookOptions<LoginMutation, LoginMutationVariables>) {
        return ApolloReactHooks.useMutation<LoginMutation, LoginMutationVariables>(LoginDocument, baseOptions);
      }
export type LoginMutationHookResult = ReturnType<typeof useLoginMutation>;
export type LoginMutationResult = ApolloReactCommon.MutationResult<LoginMutation>;
export type LoginMutationOptions = ApolloReactCommon.BaseMutationOptions<LoginMutation, LoginMutationVariables>;