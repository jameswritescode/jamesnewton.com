import * as React from 'react'
import styled from 'styled-components'

import Head from '~helpers/Head'
import { Flex } from '~ui/Elements'

import { Code, Header, Container } from './styles'

const HideOnMobile = styled(Flex)`
  align-items: center;

  @media (max-width: 52em) {
    display: none;
  }
`

type Heading = {
  company: string,
  period: string,
  skills: Array<string>,
  title: string,
}

function Heading({ skills, period, title, company }: Heading) {
  return (
    <Flex alignItems="center">
      <h3>{company}</h3>
      <Code ml="1rem"><strong>{period}</strong></Code>
      <Code ml="1rem"><strong>{title}</strong></Code>

      <HideOnMobile>
        {skills.map(skill => <Code key={skill} ml="1rem">{skill}</Code>)}
      </HideOnMobile>
    </Flex>
  )
}

export default function Resume() {
  return (
    <Container>
      <Head
        meta={{
          description: 'James Newton is a Software Engineer in Seattle',
          title: 'Resume | James Newton',
          type: 'profile',
          url: 'https://jamesnewton.com/resume',
        }}
      />

      <Header back />

      <h2>What I&rsquo;m doing</h2>

      <Heading
        company="Shopify"
        period="2021 &mdash; Current"
        skills={['Rails', 'GraphQL', 'React', 'TypeScript']}
        title="Senior Developer"
      />

      <p>
        Making Commerce Better for Everyone. Shopify is supporting the next generation of entrepreneurs, the
        world&rsquo;s biggest brands, and everyone in between.
      </p>

      <p>I work in Retail developing software that powers our Point of Sale offerings.</p>

      <p>
        Previously I worked in Solutions RnD, part of Professional Services. My work was focused on planning
        and implementing technical solutions for strategic projects brought on by partners and merchants that
        touch various parts of the ecosystem.
      </p>

      <h2>What I&rsquo;ve done</h2>

      <Heading
        company="ShareGrid"
        period="2017 &mdash; 2021"
        skills={['Rails', 'GraphQL', 'React', 'Flow & TypeScript', 'Elasticsearch', 'AWS']}
        title="Lead Engineer"
      />

      <p>
        ShareGrid is an online marketplace for sharing film and photography equipment.
      </p>

      <p>
        Joining as the second full-time engineer, my responsibilities over time included working with early
        contractors to review and deploy updates to the application, interviewing as we grew our small team,
        mentoring new employees, all while collaborating to deliver the best experience we could to our users.
      </p>

      <p>
        Being a small startup, I wore many hats. I worked closely with the product and operations teams to
        discuss, plan, build and release changes to all parts of the application and infrastructure.
      </p>

      <Heading
        company="IZEA"
        period="2016 &mdash; 2017"
        skills={['Rails', 'Ember.js', 'JSON:API']}
        title="Software Engineer"
      />

      <p>IZEA connects brands with influential content creators and publishers.</p>

      <p>
        I worked on a steady stream of APIs that powered the Rails backend of the IZEA Exchange and the mobile
        applications, occasionally working on the frontend Ember application using those APIs.
      </p>

      <Heading
        company="Code School"
        period="2014 &mdash; 2016"
        skills={['Angular.js', 'Rails', 'Node', 'Python']}
        title="Software Engineer II"
      />

      <p>Code School, eventually acquired by Pluralsight, was an interactive code learning platform.</p>

      <p>
        I worked in the courses team writing unit tests designed to be run against user submitted code from
        our interactive challenge interface. Users would watch short videos followed by a series of challenges
        where they wrote and submit code. Tests run against the code used AST parsing and sandboxed execution
        to give the user detailed feedback for completing the challenge, or let them continue if all passed. I
        implemented challenges for Surviving APIs with Rails, Staying Sharp with Angular.js, and more.
      </p>

      <p>
        I wrote the Python code executor that powered the execution and testing of user submitted code for Try
        Python and Flying Through Python, and contributed to the backend and Angular.js code for
        JavaScript.com&rsquo;s Try JavaScript.
      </p>

      <Heading
        company="Chargify"
        period="2012 &mdash; 2014"
        skills={['Rails', 'RubyGems']}
        title="Tech Support Developer"
      />

      <p>Chargify is a recurring billing platform.</p>

      <p>
        As the first hire of Tier 2 support, I was responsible for helping customers and developers with
        platform and API issues. I handled support through Zendesk and phone calls, addressing issues with
        implementation and usage of the application.
      </p>

      <p>
        I also helped develop features for payment gateway integrations, as well as the platforms initial
        ActiveMerchant gateway support for the eWay payment processor.
      </p>

      <Heading
        company="CYber SYtes"
        period="2011 &mdash; 2012"
        skills={['PHP', 'Perl', 'WordPress']}
        title="Support"
      />

      <p>
        I was responsible for handling customer support calls and tickets related to website hosting,
        migrations and troubleshooting, email management and client setup, WordPress installation and
        updates, and programming tasks related to custom client CMS&rsquo; and internal tooling.
      </p>

      <h2>Other Projects</h2>

      <Heading
        company="WhatPulse"
        period="2011 &mdash; Present"
        skills={['PHP', 'Rails', 'React', 'GraphQL']}
        title="Partner"
      />

      <p>
        WhatPulse is a desktop application that collects keyboard, mouse, application, and network usage. The
        data can be sent to the web application (pulsed) for personal analysis and competition.
      </p>

      <p>
        As a fan of data-driven software, I&rsquo;ve contributed to the web application for several years in
        the form of backend work and consulting, partnering up to build a more B2B offering.
      </p>

      <Heading
        company="GitLab"
        period="2015 &mdash; 2018"
        skills={['Rails', 'IRC']}
        title="Contributor"
      />

      <p>
        I was a member of the core team of volunteers for GitLab, having contributed and{' '}
        <a href="https://about.gitlab.com/community/mvp/">been recognized</a> for supporting users in the
        #gitlab IRC channel for several years.
      </p>

      <p>
        <a href="mailto:hello@jamesnewton.com">
          Email me today
        </a>
      </p>
    </Container>
  )
}

Resume.route = '/resume'
