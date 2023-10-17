import * as React from 'react'
import styled from 'styled-components'

import Head from '~helpers/Head'
import { Flex } from '~ui/Elements'

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
  href?: string,
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

      <p>This is the equipment I use for work and play.</p>

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
            href="https://www.amazon.com/dp/B004LWH79A"
            line="top"
            src="/gear/dbx286s.png"
            text="dbx 286s Mic Pre-amp Processor"
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
          <h2>Video</h2>

          <Item
            src="/gear/27gr95qe-b.png"
            text="LG OLED QHD 27-Inch UltraGear Monitor"
          />

          <Item
            src="/gear/27bl85u-w.png"
            text="LG 4K UHD 27-Inch Monitor"
          />
        </Flex>

        <Flex flexDirection="column" width="50rem">
          <h2>Development</h2>

          <Item
            href="https://www.apple.com/macbook-pro-14-and-16/"
            src="/gear/macbook.png"
            text="MacBook Pro (14-inch, 2023)"
          />

          <Item
            href="https://www.zsa.io/moonlander/"
            src="/gear/keyboard.png"
            text="ZSA Moonlander"
          />

          <Item
            line="top"
            src="/gear/holypanda.png"
            text="Holy Panda Switches"
          />

          <Item
            href="https://www.amazon.com/gp/product/B00BIFNTMC/"
            src="/gear/mouse.png"
            text="Anker Vertical Ergonomic Mouse"
          />
        </Flex>

        <Flex flexDirection="column" width="50rem">
          <h2>Gaming</h2>

          <Item
            line="bottom"
            src="/gear/gpu.png"
            text="Nvidia GeForce RTX™ 3070 Ti"
          />

          <Item
            href="https://www.amazon.com/dp/B08WBYQQ8C"
            src="/gear/motherboard.png"
            text="MSI Z590 Pro WIFI (CEC)"
          />

          <Item
            href="https://www.amazon.com/dp/B08X6KQSZ1"
            line="top"
            src="/gear/cpu.png"
            text="Intel Core i9-11900KF 8-Core 3.5GHz"
          />

          <Item
            href="https://www.pcgamingrace.com/products/gmmk-full-brown-switch"
            src="/gear/gmmk.png"
            text="GMMK"
          />

          <Item
            href="https://www.pcgamingrace.com/products/glorious-panda-mechanical-switches"
            line="top"
            src="/gear/glorious-panda.png"
            text="Glorious Panda Switches"
          />

          <Item
            href="https://www.pcgamingrace.com/products/glorious-aura-keycaps-v2-black"
            line="top"
            src="/gear/glorious-aura.png"
            text="Glorious Aura Keycaps"
          />

          <Item
            href="https://www.amazon.com/dp/product/B07GBZ4Q68/"
            src="/gear/logitech-hero.png"
            text="Logitech G502 HERO"
          />
        </Flex>

        <Flex flexDirection="column" width="50rem">
          <h2>Accessories</h2>

          <Item
            href="https://www.amazon.com/Logitech-BRIO-Conferencing-Recording-Streaming/dp/B01N5UOYC4"
            src="/gear/brio.png"
            text="Logitech BRIO"
          />

          <Item
            href="https://www.amazon.com/gp/product/B06XKNZT1P/"
            src="/gear/streamdeck.png"
            text="Elgato Stream Deck"
          />
        </Flex>

        <Flex flexDirection="column" width="50rem">
          <h2>Desk</h2>

          <Item
            href="https://www.upliftdesk.com/uplift-v2-standing-desk-v2-or-v2-commercial/"
            src="/gear/uplift.png"
            text="UPLIFT Standing Desk V2-Commercial"
          />

          <Item
            href="https://www.hermanmiller.com/products/seating/office-chairs/embody-chairs/"
            src="/gear/chair.png"
            text="Herman Miller Embody"
          />
        </Flex>

        <Flex flexDirection="column" width="50rem">
          <h2>EDC</h2>

          <Item
            href="https://www.apple.com/shop/buy-iphone/iphone-14"
            src="/gear/iphone.png"
            text="iPhone 14"
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
