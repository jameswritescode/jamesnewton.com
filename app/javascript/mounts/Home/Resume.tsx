import * as React from 'react'
import styled from 'styled-components'

import Flex from '~ui/Flex'

import { Code, Header } from './styles'

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
    <>
      <Header back />

      <p>I enjoy working with people to solve human and technical problems</p>

      <h2>What I&rsquo;m doing</h2>

      <Heading
        company="ShareGrid"
        period="2017 &mdash; Current"
        skills={['Rails', 'GraphQL', 'React + Flow', 'Elasticsearch', 'AWS']}
        title="Lead Engineer"
      />

      <blockquote>
        <q>
          ShareGrid is an online marketplace for sharing film and photography equipment with other people in
          your city.
        </q>
      </blockquote>

      <p>
        I joined early in 2017 as the second full-time engineer. My responsibilities over time have included
        working with early contractors to deliver updates to the application, interviewing as we grew our
        small team, mentoring new employees, while collaborating to deliver major features to our users
      </p>

      <h2>What I&rsquo;ve done</h2>

      <Heading
        company="IZEA"
        period="2016 &mdash; 2017"
        skills={['Rails', 'Ember.js', 'JSON:API']}
        title="Software Engineer"
      />

      <p>IZEA connects brands with influential content creators and publishers</p>

      <p>
        I worked on a steady stream of APIs that powered the Rails backend of the IZEA Exchange and the mobile
        applications, occasionally working on the frontend Ember application using those APIs
      </p>

      <Heading
        company="Code School"
        period="2014 &mdash; 2016"
        skills={['Angular.js', 'Rails', 'Node', 'Python']}
        title="Software Engineer II"
      />

      <p>Code School, eventually acquired by Pluralsight, was an interactive code learning platform</p>

      <p>
        I implemented challenges for the courses Surviving APIs with Rails, Staying Sharp with Angular.js,
        and more. I wrote the Python code executor that powered user code execution and testing of submissions
        for Try Python and Flying Through Python, and contributed to the backend and Angular.js code for
        JavaScript.com&rsquo;s Try JavaScript
      </p>

      <Heading
        company="Chargify"
        period="2012 &mdash; 2014"
        skills={['Rails', 'RubyGems']}
        title="Tech Support Developer"
      />

      <p>Chargify is a recurring billing platform</p>

      <p>
        As the first hire of Tier 2 support, I was responsible for helping customers and developers with
        platform and API issues. I handled support through Zendesk and phone calls, addressing issues with
        implementation and usage of the application
      </p>

      <p>
        I also helped develop features for payment gateway integrations, as well as the <em>platforms</em>
        {' '}initial ActiveMerchant gateway support for the eWay payment processor
      </p>

      <Heading
        company="CYber SYtes"
        period="2011 &mdash; 2012"
        skills={['PHP', 'Perl', 'WordPress']}
        title="Support"
      />

      <p>
        I was responsible for various programming, debugging, and a wide range of phone and ticket based
        support tasks while working at this small website shop in my hometown
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
        data can be sent to the web application (pulsed) for personal analysis and competition
      </p>

      <p>
        As a fan of data-driven software, I&rsquo;ve contributed to the web application for several years in
        the form of backend work and consulting. I&rsquo;m currently working on an undisclosed project
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
        #gitlab IRC channel for several years
      </p>

      <p>
        <a href="mailto:hello@jamesnewton.com">
          Email me today
        </a>
      </p>
    </>
  )
}
