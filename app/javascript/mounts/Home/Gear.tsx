import * as React from 'react'
import styled from 'styled-components'

import Flex from '~ui/Flex'
import Head from '~helpers/Head'

import { Header } from './styles'

type Direction = 'top' | 'bottom' | null

const ItemFlex = styled.a<{ line: Direction }>`
  align-items: center;
  background-color: ${props => props.theme.secondary};
  border-radius: ${props => props.theme.borderRadius};
  border: 1px solid ${props => props.theme.primary};
  display: flex;
  margin-bottom: 1rem;
  padding: 0 1rem;
  position: relative;
  height: 8.2rem;

  :last-child {
    margin-bottom: 0;
  }

  && {
    // Disable our global anchor decoration
    :after {
      content: '';
    }

    :hover {
      background-color: ${props => props.theme.primary};
      color: ${props => props.theme.secondary};
      z-index: 2;

      :before, :after {
        background-color: ${props => props.theme.primary};
      }
    }

    ${({ line, theme }) => line && `
      :${line === 'top' ? 'before' : 'after'} {
        background-color: ${theme.secondary};
        border-left: 1px solid ${theme.primary};
        border-right: 1px solid ${theme.primary};
        content: '';
        height: 1.2rem;
        left: 4.6rem;
        position: absolute;
        ${line === 'top' ? 'bottom' : 'top'}: 8rem;
        width: 1rem;
        z-index: 1;
      }
    `}
  }

  img {
    height: 8rem;
    margin-right: 1rem;
    object-fit: contain;
    width: 8rem;
  }
`

type Item = {
  href: string,
  line?: Direction,
  src?: string,
  text: string,
}

function Item({ text, href, src, line }: Item) {
  return (
    <ItemFlex
      href={href}
      line={line}
      rel="noreferrer"
      target="_blank"
    >
      {src && <img loading="lazy" src={src} />}
      {text}
    </ItemFlex>
  )
}

Item.defaultProps = {
  line: null,
  src: null,
}

const Container = styled(Flex)`
  flex-wrap: wrap;

  // Negates the layout padding so wrapping looks better
  margin-left: -1rem;

  > div {
    margin: 0 1rem;

    :last-child {
      margin-right: 0;
    }
  }

  @media(max-width: 1080px) {
    margin-left: 0;

    > div {
      margin: 0;
      width: 100%;
    }
  }
`

export default function Gear() {
  const p2715q = (
    <Item
      href="#"
      line="bottom"
      src="/gear/p2715q.png"
      text="Dell Ultra 4k 27-Inch Monitor"
    />
  )

  return (
    <>
      <Head
        meta={{
          description: 'James Newton is a Software Engineer in Seattle',
          title: 'Gear | James Newton',
          type: 'profile',
          url: 'https://jamesnewton.com/gear',
        }}
      />

      <Header back title="Gear" />

      <p>This is the equipment I use for work and play</p>

      <p>
        Audio is available to both my Development and Gaming machines via a{' '}
        <a href="https://www.amazon.com/gp/product/B07TS5JNT3/">USB Switch</a>
      </p>

      <Container>
        <Flex flexDirection="column" width="50rem">
          <h2>Audio</h2>

          <Item
            href="https://www.amazon.com/gp/product/B00018MSNI/"
            line="bottom"
            src="/gear/headphones.png"
            text="Sennheiser HD 650"
          />

          <Item
            href="https://www.schiit.com/products/magni-1"
            line="bottom"
            src="/gear/amp.png"
            text="Schiit Magni 3+"
          />

          <Item
            href="https://www.amazon.com/gp/product/B07QR6Z1JB/"
            src="/gear/interface.png"
            text="Scarlett Solo"
          />

          <Item
            href="https://www.amazon.com/gp/product/B004MQSV04/"
            line="top"
            src="/gear/cloudlifter.png"
            text="Cloudlifter CL-1"
          />

          <Item
            href="https://www.amazon.com/gp/product/B0002E4Z8M/"
            line="top"
            src="/gear/mic.png"
            text="Shure SM7B"
          />

          <Item
            href="https://www.amazon.com/gp/product/B001D7UYBO/"
            line="top"
            src="/gear/boom.png"
            text="RODE PSA 1 Boom Arm"
          />
        </Flex>

        <Flex flexDirection="column" width="50rem">
          <h2>Development</h2>

          <Item
            href="https://www.amazon.com/gp/product/B00PXYRMPE/"
            line="bottom"
            src="/gear/u3415w.png"
            text="Dell UltraSharp 34-Inch Curved Monitor"
          />

          <Item
            href="#"
            line="bottom"
            src="/gear/arms.png"
            text="Monoprice Dual Monitor Desk Mount"
          />

          {p2715q}

          <Item
            href="https://www.apple.com/macbook-pro-16/"
            src="/gear/macbook.png"
            text="MacBook Pro (16-inch, 2019)"
          />

          <Item
            href="https://www.amazon.com/gp/product/B0146YF1FO"
            src="/gear/apple-keyboard.png"
            text="Apple Wireless Keyboard"
          />

          <Item
            href="https://www.apple.com/shop/product/MJ2R2LL/A/magic-trackpad-2-silver"
            src="/gear/trackpad.png"
            text="Magic Trackpad"
          />
        </Flex>

        <Flex flexDirection="column" width="50rem">
          <h2>Gaming</h2>

          {p2715q}

          <Item
            href="https://www.amazon.com/gp/product/B06Y15DWXR/"
            line="bottom"
            src="/gear/gpu.png"
            text="EVGA GeForce GTX 1080 Ti"
          />

          <Item
            href="https://www.amazon.com/gp/product/B00D12OBEU/"
            src="/gear/motherboard.png"
            text="MSI Z87-G45 Motherboard"
          />

          <Item
            href="https://www.amazon.com/gp/product/B00CO8TBQ0/"
            line="top"
            src="/gear/cpu.png"
            text="Intel Core i7-4770K Processor"
          />

          <Item
            href="https://www.amazon.com/gp/product/B00N4OBCWY/"
            src="/gear/k95.png"
            text="Corsair K95 RGB Cherry MX Red"
          />
        </Flex>

        <Flex flexDirection="column" width="50rem">
          <h2>Desk</h2>

          <Item
            href="https://www.autonomous.ai/office-chairs/ergonomic-chair"
            src="/gear/chair.png"
            text="ErgoChair 2"
          />

          <Item
            href="https://www.amazon.com/stores/FLEXISPOT/FLEXISPOT/page/DC73F9D6-1819-4EA6-A8A0-73BAF9007518"
            text="2x Flexispot Adjustable Desk Frame"
          />
        </Flex>

        <Flex flexDirection="column" width="50rem">
          <h2>EDC</h2>

          <Item
            href="https://www.apple.com/shop/refurbished/iphone/iphone-x"
            src="/gear/iphone.png"
            text="iPhone X"
          />

          <Item
            href="https://www.apple.com/airpods-pro/"
            src="/gear/airpods.png"
            text="AirPods Pro"
          />
        </Flex>
      </Container>
    </>
  )
}

Gear.route = '/gear'
