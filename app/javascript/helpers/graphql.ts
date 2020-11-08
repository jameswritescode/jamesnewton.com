import * as Apollo from '@apollo/client';
export type Maybe<T> = T | null;
export type Exact<T extends { [key: string]: unknown }> = { [K in keyof T]: T[K] };
const gql = Apollo.gql;
/** All built-in and custom scalars, mapped to their actual values */
export type Scalars = {
  ID: string;
  String: string;
  Boolean: boolean;
  Int: number;
  Float: number;
  Upload: any;
};

export type Attachment = Node & {
  __typename?: 'Attachment';
  embed: Scalars['Boolean'];
  extension: Scalars['String'];
  filename: Scalars['String'];
  id?: Maybe<Scalars['ID']>;
  url: Scalars['String'];
};

/** Autogenerated input type of CreateAttachment */
export type CreateAttachmentInput = {
  /** A unique identifier for the client performing the mutation. */
  clientMutationId?: Maybe<Scalars['String']>;
  file: Scalars['Upload'];
};

/** Autogenerated return type of CreateAttachment */
export type CreateAttachmentPayload = {
  __typename?: 'CreateAttachmentPayload';
  /** A unique identifier for the client performing the mutation. */
  clientMutationId?: Maybe<Scalars['String']>;
  success: Scalars['Boolean'];
  url?: Maybe<Scalars['String']>;
};

/** Autogenerated input type of DestroyPost */
export type DestroyPostInput = {
  /** A unique identifier for the client performing the mutation. */
  clientMutationId?: Maybe<Scalars['String']>;
  slug: Scalars['String'];
};

/** Autogenerated return type of DestroyPost */
export type DestroyPostPayload = {
  __typename?: 'DestroyPostPayload';
  /** A unique identifier for the client performing the mutation. */
  clientMutationId?: Maybe<Scalars['String']>;
  success: Scalars['Boolean'];
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

/** Autogenerated input type of Logout */
export type LogoutInput = {
  /** A unique identifier for the client performing the mutation. */
  clientMutationId?: Maybe<Scalars['String']>;
};

/** Autogenerated return type of Logout */
export type LogoutPayload = {
  __typename?: 'LogoutPayload';
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
  createAttachment: CreateAttachmentPayload;
  destroyPost?: Maybe<DestroyPostPayload>;
  login: LoginPayload;
  logout?: Maybe<LogoutPayload>;
  updateOrCreatePost: UpdateOrCreatePostPayload;
};


export type MutationCreateAttachmentArgs = {
  input: CreateAttachmentInput;
};


export type MutationDestroyPostArgs = {
  input: DestroyPostInput;
};


export type MutationLoginArgs = {
  input: LoginInput;
};


export type MutationLogoutArgs = {
  input: LogoutInput;
};


export type MutationUpdateOrCreatePostArgs = {
  input: UpdateOrCreatePostInput;
};

export type Node = {
  id?: Maybe<Scalars['ID']>;
};

export type Post = Node & {
  __typename?: 'Post';
  content: Scalars['String'];
  created: Scalars['String'];
  id?: Maybe<Scalars['ID']>;
  meta: Meta;
  name: Scalars['String'];
  slug: Scalars['String'];
  state: PostState;
  url: Scalars['String'];
};

export enum PostState {
  Draft = 'draft',
  Published = 'published'
}

export type Query = {
  __typename?: 'Query';
  attachments: Array<Maybe<Attachment>>;
  latestTweet: Tweet;
  me?: Maybe<User>;
  post?: Maybe<Post>;
  posts: Array<Maybe<Post>>;
};


export type QueryPostArgs = {
  slug: Scalars['String'];
};


export type QueryPostsArgs = {
  limit?: Maybe<Scalars['Int']>;
};

export type Tweet = {
  __typename?: 'Tweet';
  content: Scalars['String'];
  created: Scalars['String'];
};

/** Autogenerated input type of UpdateOrCreatePost */
export type UpdateOrCreatePostInput = {
  /** A unique identifier for the client performing the mutation. */
  clientMutationId?: Maybe<Scalars['String']>;
  content?: Maybe<Scalars['String']>;
  id?: Maybe<Scalars['ID']>;
  name?: Maybe<Scalars['String']>;
  state?: Maybe<PostState>;
};

/** Autogenerated return type of UpdateOrCreatePost */
export type UpdateOrCreatePostPayload = {
  __typename?: 'UpdateOrCreatePostPayload';
  /** A unique identifier for the client performing the mutation. */
  clientMutationId?: Maybe<Scalars['String']>;
  post: Post;
  success: Scalars['Boolean'];
};


export type User = Node & {
  __typename?: 'User';
  id?: Maybe<Scalars['ID']>;
};

export type PostsQueryVariables = Exact<{ [key: string]: never; }>;


export type PostsQuery = (
  { __typename?: 'Query' }
  & { posts: Array<Maybe<(
    { __typename?: 'Post' }
    & Pick<Post, 'id' | 'created' | 'name' | 'slug' | 'state' | 'url'>
  )>> }
);

export type PostQueryVariables = Exact<{
  slug: Scalars['String'];
}>;


export type PostQuery = (
  { __typename?: 'Query' }
  & { post?: Maybe<(
    { __typename?: 'Post' }
    & Pick<Post, 'id' | 'content' | 'created' | 'name' | 'state'>
    & { meta: (
      { __typename?: 'Meta' }
      & Pick<Meta, 'description' | 'title' | 'type' | 'url'>
    ) }
  )> }
);

export type DestroyPostMutationVariables = Exact<{
  input: DestroyPostInput;
}>;


export type DestroyPostMutation = (
  { __typename?: 'Mutation' }
  & { destroyPost?: Maybe<(
    { __typename?: 'DestroyPostPayload' }
    & Pick<DestroyPostPayload, 'success'>
  )> }
);

export type HomeQueryVariables = Exact<{ [key: string]: never; }>;


export type HomeQuery = (
  { __typename?: 'Query' }
  & { latestTweet: (
    { __typename?: 'Tweet' }
    & Pick<Tweet, 'content' | 'created'>
  ), posts: Array<Maybe<(
    { __typename?: 'Post' }
    & Pick<Post, 'id' | 'created' | 'name' | 'slug' | 'state' | 'url'>
  )>> }
);

export type MeQueryVariables = Exact<{ [key: string]: never; }>;


export type MeQuery = (
  { __typename?: 'Query' }
  & { me?: Maybe<(
    { __typename?: 'User' }
    & Pick<User, 'id'>
  )> }
);

export type CreateAttachmentMutationVariables = Exact<{
  input: CreateAttachmentInput;
}>;


export type CreateAttachmentMutation = (
  { __typename?: 'Mutation' }
  & { createAttachment: (
    { __typename?: 'CreateAttachmentPayload' }
    & Pick<CreateAttachmentPayload, 'success' | 'url'>
  ) }
);

export type UpdateOrCreatePostMutationVariables = Exact<{
  input: UpdateOrCreatePostInput;
}>;


export type UpdateOrCreatePostMutation = (
  { __typename?: 'Mutation' }
  & { updateOrCreatePost: (
    { __typename?: 'UpdateOrCreatePostPayload' }
    & Pick<UpdateOrCreatePostPayload, 'success'>
    & { post: (
      { __typename?: 'Post' }
      & Pick<Post, 'id' | 'slug' | 'url'>
    ) }
  ) }
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

export type LogoutMutationVariables = Exact<{
  input: LogoutInput;
}>;


export type LogoutMutation = (
  { __typename?: 'Mutation' }
  & { logout?: Maybe<(
    { __typename?: 'LogoutPayload' }
    & Pick<LogoutPayload, 'success'>
  )> }
);

export type AttachmentsQueryVariables = Exact<{ [key: string]: never; }>;


export type AttachmentsQuery = (
  { __typename?: 'Query' }
  & { attachments: Array<Maybe<(
    { __typename?: 'Attachment' }
    & Pick<Attachment, 'id' | 'embed' | 'extension' | 'filename' | 'url'>
  )>> }
);


export const PostsDocument = gql`
    query Posts {
  posts {
    id
    created
    name
    slug
    state
    url
  }
}
    `;

/**
 * __usePostsQuery__
 *
 * To run a query within a React component, call `usePostsQuery` and pass it any options that fit your needs.
 * When your component renders, `usePostsQuery` returns an object from Apollo Client that contains loading, error, and data properties
 * you can use to render your UI.
 *
 * @param baseOptions options that will be passed into the query, supported options are listed on: https://www.apollographql.com/docs/react/api/react-hooks/#options;
 *
 * @example
 * const { data, loading, error } = usePostsQuery({
 *   variables: {
 *   },
 * });
 */
export function usePostsQuery(baseOptions?: Apollo.QueryHookOptions<PostsQuery, PostsQueryVariables>) {
        return Apollo.useQuery<PostsQuery, PostsQueryVariables>(PostsDocument, baseOptions);
      }
export function usePostsLazyQuery(baseOptions?: Apollo.LazyQueryHookOptions<PostsQuery, PostsQueryVariables>) {
          return Apollo.useLazyQuery<PostsQuery, PostsQueryVariables>(PostsDocument, baseOptions);
        }
export type PostsQueryHookResult = ReturnType<typeof usePostsQuery>;
export type PostsLazyQueryHookResult = ReturnType<typeof usePostsLazyQuery>;
export type PostsQueryResult = Apollo.QueryResult<PostsQuery, PostsQueryVariables>;
export const PostDocument = gql`
    query Post($slug: String!) {
  post(slug: $slug) {
    id
    content
    created
    name
    state
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
export function usePostQuery(baseOptions?: Apollo.QueryHookOptions<PostQuery, PostQueryVariables>) {
        return Apollo.useQuery<PostQuery, PostQueryVariables>(PostDocument, baseOptions);
      }
export function usePostLazyQuery(baseOptions?: Apollo.LazyQueryHookOptions<PostQuery, PostQueryVariables>) {
          return Apollo.useLazyQuery<PostQuery, PostQueryVariables>(PostDocument, baseOptions);
        }
export type PostQueryHookResult = ReturnType<typeof usePostQuery>;
export type PostLazyQueryHookResult = ReturnType<typeof usePostLazyQuery>;
export type PostQueryResult = Apollo.QueryResult<PostQuery, PostQueryVariables>;
export const DestroyPostDocument = gql`
    mutation DestroyPost($input: DestroyPostInput!) {
  destroyPost(input: $input) {
    success
  }
}
    `;
export type DestroyPostMutationFn = Apollo.MutationFunction<DestroyPostMutation, DestroyPostMutationVariables>;

/**
 * __useDestroyPostMutation__
 *
 * To run a mutation, you first call `useDestroyPostMutation` within a React component and pass it any options that fit your needs.
 * When your component renders, `useDestroyPostMutation` returns a tuple that includes:
 * - A mutate function that you can call at any time to execute the mutation
 * - An object with fields that represent the current status of the mutation's execution
 *
 * @param baseOptions options that will be passed into the mutation, supported options are listed on: https://www.apollographql.com/docs/react/api/react-hooks/#options-2;
 *
 * @example
 * const [destroyPostMutation, { data, loading, error }] = useDestroyPostMutation({
 *   variables: {
 *      input: // value for 'input'
 *   },
 * });
 */
export function useDestroyPostMutation(baseOptions?: Apollo.MutationHookOptions<DestroyPostMutation, DestroyPostMutationVariables>) {
        return Apollo.useMutation<DestroyPostMutation, DestroyPostMutationVariables>(DestroyPostDocument, baseOptions);
      }
export type DestroyPostMutationHookResult = ReturnType<typeof useDestroyPostMutation>;
export type DestroyPostMutationResult = Apollo.MutationResult<DestroyPostMutation>;
export type DestroyPostMutationOptions = Apollo.BaseMutationOptions<DestroyPostMutation, DestroyPostMutationVariables>;
export const HomeDocument = gql`
    query Home {
  latestTweet {
    content
    created
  }
  posts(limit: 3) {
    id
    created
    name
    slug
    state
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
export function useHomeQuery(baseOptions?: Apollo.QueryHookOptions<HomeQuery, HomeQueryVariables>) {
        return Apollo.useQuery<HomeQuery, HomeQueryVariables>(HomeDocument, baseOptions);
      }
export function useHomeLazyQuery(baseOptions?: Apollo.LazyQueryHookOptions<HomeQuery, HomeQueryVariables>) {
          return Apollo.useLazyQuery<HomeQuery, HomeQueryVariables>(HomeDocument, baseOptions);
        }
export type HomeQueryHookResult = ReturnType<typeof useHomeQuery>;
export type HomeLazyQueryHookResult = ReturnType<typeof useHomeLazyQuery>;
export type HomeQueryResult = Apollo.QueryResult<HomeQuery, HomeQueryVariables>;
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
export function useMeQuery(baseOptions?: Apollo.QueryHookOptions<MeQuery, MeQueryVariables>) {
        return Apollo.useQuery<MeQuery, MeQueryVariables>(MeDocument, baseOptions);
      }
export function useMeLazyQuery(baseOptions?: Apollo.LazyQueryHookOptions<MeQuery, MeQueryVariables>) {
          return Apollo.useLazyQuery<MeQuery, MeQueryVariables>(MeDocument, baseOptions);
        }
export type MeQueryHookResult = ReturnType<typeof useMeQuery>;
export type MeLazyQueryHookResult = ReturnType<typeof useMeLazyQuery>;
export type MeQueryResult = Apollo.QueryResult<MeQuery, MeQueryVariables>;
export const CreateAttachmentDocument = gql`
    mutation CreateAttachment($input: CreateAttachmentInput!) {
  createAttachment(input: $input) {
    success
    url
  }
}
    `;
export type CreateAttachmentMutationFn = Apollo.MutationFunction<CreateAttachmentMutation, CreateAttachmentMutationVariables>;

/**
 * __useCreateAttachmentMutation__
 *
 * To run a mutation, you first call `useCreateAttachmentMutation` within a React component and pass it any options that fit your needs.
 * When your component renders, `useCreateAttachmentMutation` returns a tuple that includes:
 * - A mutate function that you can call at any time to execute the mutation
 * - An object with fields that represent the current status of the mutation's execution
 *
 * @param baseOptions options that will be passed into the mutation, supported options are listed on: https://www.apollographql.com/docs/react/api/react-hooks/#options-2;
 *
 * @example
 * const [createAttachmentMutation, { data, loading, error }] = useCreateAttachmentMutation({
 *   variables: {
 *      input: // value for 'input'
 *   },
 * });
 */
export function useCreateAttachmentMutation(baseOptions?: Apollo.MutationHookOptions<CreateAttachmentMutation, CreateAttachmentMutationVariables>) {
        return Apollo.useMutation<CreateAttachmentMutation, CreateAttachmentMutationVariables>(CreateAttachmentDocument, baseOptions);
      }
export type CreateAttachmentMutationHookResult = ReturnType<typeof useCreateAttachmentMutation>;
export type CreateAttachmentMutationResult = Apollo.MutationResult<CreateAttachmentMutation>;
export type CreateAttachmentMutationOptions = Apollo.BaseMutationOptions<CreateAttachmentMutation, CreateAttachmentMutationVariables>;
export const UpdateOrCreatePostDocument = gql`
    mutation UpdateOrCreatePost($input: UpdateOrCreatePostInput!) {
  updateOrCreatePost(input: $input) {
    success
    post {
      id
      slug
      url
    }
  }
}
    `;
export type UpdateOrCreatePostMutationFn = Apollo.MutationFunction<UpdateOrCreatePostMutation, UpdateOrCreatePostMutationVariables>;

/**
 * __useUpdateOrCreatePostMutation__
 *
 * To run a mutation, you first call `useUpdateOrCreatePostMutation` within a React component and pass it any options that fit your needs.
 * When your component renders, `useUpdateOrCreatePostMutation` returns a tuple that includes:
 * - A mutate function that you can call at any time to execute the mutation
 * - An object with fields that represent the current status of the mutation's execution
 *
 * @param baseOptions options that will be passed into the mutation, supported options are listed on: https://www.apollographql.com/docs/react/api/react-hooks/#options-2;
 *
 * @example
 * const [updateOrCreatePostMutation, { data, loading, error }] = useUpdateOrCreatePostMutation({
 *   variables: {
 *      input: // value for 'input'
 *   },
 * });
 */
export function useUpdateOrCreatePostMutation(baseOptions?: Apollo.MutationHookOptions<UpdateOrCreatePostMutation, UpdateOrCreatePostMutationVariables>) {
        return Apollo.useMutation<UpdateOrCreatePostMutation, UpdateOrCreatePostMutationVariables>(UpdateOrCreatePostDocument, baseOptions);
      }
export type UpdateOrCreatePostMutationHookResult = ReturnType<typeof useUpdateOrCreatePostMutation>;
export type UpdateOrCreatePostMutationResult = Apollo.MutationResult<UpdateOrCreatePostMutation>;
export type UpdateOrCreatePostMutationOptions = Apollo.BaseMutationOptions<UpdateOrCreatePostMutation, UpdateOrCreatePostMutationVariables>;
export const LoginDocument = gql`
    mutation Login($input: LoginInput!) {
  login(input: $input) {
    success
  }
}
    `;
export type LoginMutationFn = Apollo.MutationFunction<LoginMutation, LoginMutationVariables>;

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
export function useLoginMutation(baseOptions?: Apollo.MutationHookOptions<LoginMutation, LoginMutationVariables>) {
        return Apollo.useMutation<LoginMutation, LoginMutationVariables>(LoginDocument, baseOptions);
      }
export type LoginMutationHookResult = ReturnType<typeof useLoginMutation>;
export type LoginMutationResult = Apollo.MutationResult<LoginMutation>;
export type LoginMutationOptions = Apollo.BaseMutationOptions<LoginMutation, LoginMutationVariables>;
export const LogoutDocument = gql`
    mutation Logout($input: LogoutInput!) {
  logout(input: $input) {
    success
  }
}
    `;
export type LogoutMutationFn = Apollo.MutationFunction<LogoutMutation, LogoutMutationVariables>;

/**
 * __useLogoutMutation__
 *
 * To run a mutation, you first call `useLogoutMutation` within a React component and pass it any options that fit your needs.
 * When your component renders, `useLogoutMutation` returns a tuple that includes:
 * - A mutate function that you can call at any time to execute the mutation
 * - An object with fields that represent the current status of the mutation's execution
 *
 * @param baseOptions options that will be passed into the mutation, supported options are listed on: https://www.apollographql.com/docs/react/api/react-hooks/#options-2;
 *
 * @example
 * const [logoutMutation, { data, loading, error }] = useLogoutMutation({
 *   variables: {
 *      input: // value for 'input'
 *   },
 * });
 */
export function useLogoutMutation(baseOptions?: Apollo.MutationHookOptions<LogoutMutation, LogoutMutationVariables>) {
        return Apollo.useMutation<LogoutMutation, LogoutMutationVariables>(LogoutDocument, baseOptions);
      }
export type LogoutMutationHookResult = ReturnType<typeof useLogoutMutation>;
export type LogoutMutationResult = Apollo.MutationResult<LogoutMutation>;
export type LogoutMutationOptions = Apollo.BaseMutationOptions<LogoutMutation, LogoutMutationVariables>;
export const AttachmentsDocument = gql`
    query Attachments {
  attachments {
    id
    embed
    extension
    filename
    url
  }
}
    `;

/**
 * __useAttachmentsQuery__
 *
 * To run a query within a React component, call `useAttachmentsQuery` and pass it any options that fit your needs.
 * When your component renders, `useAttachmentsQuery` returns an object from Apollo Client that contains loading, error, and data properties
 * you can use to render your UI.
 *
 * @param baseOptions options that will be passed into the query, supported options are listed on: https://www.apollographql.com/docs/react/api/react-hooks/#options;
 *
 * @example
 * const { data, loading, error } = useAttachmentsQuery({
 *   variables: {
 *   },
 * });
 */
export function useAttachmentsQuery(baseOptions?: Apollo.QueryHookOptions<AttachmentsQuery, AttachmentsQueryVariables>) {
        return Apollo.useQuery<AttachmentsQuery, AttachmentsQueryVariables>(AttachmentsDocument, baseOptions);
      }
export function useAttachmentsLazyQuery(baseOptions?: Apollo.LazyQueryHookOptions<AttachmentsQuery, AttachmentsQueryVariables>) {
          return Apollo.useLazyQuery<AttachmentsQuery, AttachmentsQueryVariables>(AttachmentsDocument, baseOptions);
        }
export type AttachmentsQueryHookResult = ReturnType<typeof useAttachmentsQuery>;
export type AttachmentsLazyQueryHookResult = ReturnType<typeof useAttachmentsLazyQuery>;
export type AttachmentsQueryResult = Apollo.QueryResult<AttachmentsQuery, AttachmentsQueryVariables>;