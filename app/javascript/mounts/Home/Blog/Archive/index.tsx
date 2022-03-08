import * as React from 'react'
import styled, { useTheme } from 'styled-components'

import Head from '~helpers/Head'
import { Block } from '~ui/Elements'
import { usePostsQuery, PostsQuery } from '~gql'

import PostLine from '../../PostLine'
import { Header, Container } from '../../styles'

const Img = styled.img`
  border-radius: ${props => props.theme.borderRadius};
  max-height: 100px;
`

interface IGrid {
  images: PostsQuery['posts'][0]['images']
}

function Grid({ images }: IGrid) {
  const theme = useTheme()

  return (
    <Block
      backgroundColor={theme.secondary}
      borderRadius={theme.borderRadius}
      display="inline-flex"
      flexWrap="wrap"
      gridGap="0.5em"
      my="0.5em"
      p="0.5em"
    >
      {images.map(image => (
        <Img
          key={image.id}
          loading="lazy"
          src={image.url}
        />
      ))}
    </Block>
  )
}

export default function Archive() {
  const { data } = usePostsQuery()

  return (
    <Container>
      <Head
        meta={{
          description: 'James Newton is a Software Engineer in Seattle',
          title: 'Archive | James Newton',
          type: 'article',
          url: 'https://jamesnewton.com/blog',
        }}
      />

      <Header back />

      {data && data.posts.map(({ id, images, ...post }) => (
        <div key={id}>
          <PostLine {...post} />

          {images.length > 0 && <Grid images={images} />}
        </div>
      ))}
    </Container>
  )
}

Archive.route = '/blog/:slug'
