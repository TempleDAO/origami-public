import { AppRoutes } from '@/app-routes';
import { Link } from '@/components/commons/Link';
import { GMX_URL, ORIGAMI_URL, TERMS_OF_SERVICE_URL } from '@/urls';
import styled from 'styled-components';

export function Page() {
  return (
    <PageContainer>
      <H1>Origami Finance Privacy Policy</H1>
      <DocDate>Last updated: June 30, 2023</DocDate>
      <p>
        This Privacy Policy is part of the Origami Finance Terms of Service
        at&nbsp;
        <Link href={AppRoutes.TermsOfService}> {TERMS_OF_SERVICE_URL}</Link>.
        All terms, conditions, and terminology are consistent with the Terms of
        Service, and the Terms of Service are incorporated into this document by
        reference.
      </p>
      <p>
        This policy governs the use of the Origami Finance website at&nbsp;
        <Link href={AppRoutes.Index}>{ORIGAMI_URL}</Link> and the associated
        tools and services.
      </p>
      <p>
        Collectively, the website and the associated tools and services are
        referred to as the “<b>Services</b>“ in these terms. The Services do not
        include outside websites or platforms which may be linked or
        interconnected to the Services. Such outside platforms may have their
        own privacy policy, which control for all transactions on such
        platforms. These outside platforms may include, but are not limited to:
      </p>
      <ul>
        <li>
          <p>
            GMX (
            <ExternalLink href={GMX_URL} target="_blank">
              {GMX_URL}
            </ExternalLink>
            )
          </p>
        </li>
      </ul>
      <p>
        Origami Foundation operates the Services. It and its affiliates are
        referred to in this document as the “operator,“ “we ,“ or “us.“
      </p>
      <h2>The Blockchain</h2>
      <p>
        Blockchain technology, also known as distributed ledger technology (or
        simply `DLT`), is at the core of our business. Blockchains are
        decentralized and made up of digitally recorded data in a chain of
        packages called `blocks`. The manner in which these blocks are linked is
        chronological, meaning that the data is very difficult to alter once
        recorded. Since the ledger may be distributed all over the world (across
        several `nodes` which usually replicate the ledger) this means there is
        no single person making decisions or otherwise administering the system
        (such as an operator of a cloud computing system), and that there is no
        centralized place where it is located either.
      </p>
      <p>
        <b>
          This means that by design, a blockchain`s records cannot be changed or
          deleted and is said to be `immutable`
        </b>
        . This may affect your ability to exercise your rights such as your
        right to erasure (`right to be forgotten`), or your rights to object or
        restrict processing of your personal data. Data on the blockchain can`t
        be erased or changed. Although smart contracts may be used to revoke
        certain access rights, and some content may be made invisible to others,
        it is not deleted.
      </p>
      <p>
        In certain circumstances, in order to comply with our contractual
        obligations to you (such as delivery of tokens) it will be necessary to
        write certain personal data, such as your wallet address, onto the
        blockchain; this requires you to execute such transactions using your
        wallet`s private key.
      </p>
      <p>
        In most cases ultimate decisions to (i) transact on the blockchain using
        your wallet address, as well as (ii) share the public key relating to
        your wallet address with anyone (including us) rests with you.
      </p>
      <p>
        <b>
          If you want to ensure your privacy rights are not affected in any way,
          you should not transact on blockchains as certain rights may not be
          fully available or exercisable by you or us due to the technological
          infrastructure of the blockchain. The blockchain is available to the
          public and any personal data shared on the blockchain will become
          publicly available.
        </b>
      </p>
      <h2>Individuals under the Age of 18</h2>
      <p>
        As per our Terms of Service, individuals under the age of 18 are not
        permitted to use the Services. As such, we do not knowingly collect,
        solicit or maintain personal data from anyone under the age of 18 or
        knowingly allow such persons to register for the Services.
      </p>
      <p>
        In the event that we learn that we have collected personal data from an
        individual under age 18, we will use commercially reasonable efforts to
        delete that information from our database. Please contact us if you have
        any concerns. If you are a parent or guardian and you are aware that
        your child has provided personal data to the Services, please contact us
        so that we may remove such data. Note that we cannot delete information
        stored on public cryptographic blockchains.
      </p>
      <h2>Collecting</h2>
      <h3>Things you and others do and provide.</h3>
      <ul>
        <li>
          <p>
            <b>Information and content you provide.</b> We collect the content,
            communications and other information you provide when you use our
            Services, including when you create an account, initiate the use of
            the Services, create or share content, and message or communicate
            with others. This information may include, but is not limited to:
          </p>
          <ul>
            <li>
              <p>Financial Information</p>
            </li>
            <li>
              <p>Payment Information</p>
            </li>
          </ul>
        </li>
        <li>
          <p>
            <b>Financial information.</b> In order to transfer funds, you may
            need to provide us and our third-party financial providers or
            partners with certain account and other payment information, such as
            information needed to make payment via cryptocurrency. You may agree
            to your personal and financial information being transferred,
            stored, and processed by such third parties in accordance with their
            respective privacy policies.
          </p>
        </li>
        <li>
          <p>
            <b>Your usage.</b> We may collect information about how you use our
            Services, such as the features you use; the actions you take; and
            the time, frequency, and duration of your activities.
          </p>
        </li>
        <li>
          <p>
            <b>Information about transactions made on our Services.</b> If you
            use our Services for transactions of any kind, we may collect
            information about them.
          </p>
        </li>
        <li>
          <p>
            <b>Things others do and information they provide about you.</b> We
            may also receive and analyze content, communications, and
            information that other people provide when they use our Services.
          </p>
        </li>
      </ul>
      <h3>Cookies</h3>
      <p>
        We, and our partners, use cookies and similar technologies to give you
        the best possible experience. Cookies are used to remember you and to
        collect information about how you interact with the Services. If you
        have an account with the Services, we may link this usage data with
        other information. You may have the option to either accept or refuse
        these cookies. If you choose to refuse, you may not be able to use some
        portions of the Services.
      </p>
      <h3>Device Information</h3>
      <p>
        As described below, we may collect information from and about the
        computers, phones, and other web-connected devices you use that interact
        with our Services, and we combine this information across different
        devices you use. Information we obtain from these devices includes:
      </p>
      <ul>
        <li>
          <p>
            <b>Cookie data:</b> data from cookies stored on your device,
            including cookie IDs and settings.
          </p>
        </li>
      </ul>
      <h3>When using the Services</h3>
      <p>
        When using the Services, we may collect and process personal data. The
        data will be stored in different instances. We may collect and use this
        information to provide you the Services and to debug issues and provide
        support.
      </p>
      <ol>
        <li>
          <p>On the Blockchain the following data may be stored:</p>
        </li>
      </ol>
      <ul>
        <li>
          <p>addresses of externally owned accounts</p>
        </li>
        <li>
          <p>transactions made; and</p>
        </li>
        <li>
          <p>token balances.</p>
        </li>
      </ul>
      <p>
        <b>
          The data will be stored on the Blockchain. Given the technological
          design of the blockchain, this data will become public and it will not
          likely be possible to delete or change the data at any given time.
        </b>
      </p>
      <ol start={2}>
        <li>
          <p>In our web servers, we will store the following data:</p>
        </li>
      </ol>
      <ul>
        <li>
          <p>addresses of externally owned accounts; and</p>
        </li>
        <li>
          <p>transactions made.</p>
        </li>
      </ul>
      <ol start={3}>
        <li>
          <p>Log Data</p>
        </li>
      </ol>
      <ul>
        <li>
          <p>the Internet protocol address (“IP address“); and</p>
        </li>
        <li>
          <p>transaction id/ Hash.</p>
        </li>
      </ul>
      <h2>Tracking and Uses</h2>
      <p>
        We use the information we have (subject to choices you make) as
        described below and to provide and support the Services. Here&apos;s
        how:
      </p>
      <h3>Provide, personalize and improve our Services.</h3>
      <p>We use the information we have to deliver our Services.</p>
      <ul>
        <li>
          <p>
            <b>Product research and development:</b> We may use the information
            we have to develop, test and improve our Services, including by
            conducting surveys and research, and testing and troubleshooting new
            products and features.
          </p>
        </li>
      </ul>
      <h3>Provide measurement, analytics, and other business services.</h3>
      <p>
        We may use the information we have (including your activity on our
        Services) to help partners measure the effectiveness and distribution of
        their ads and services, and understand the types of people who use their
        services and how people interact with their websites, apps, and
        services.
      </p>
      <h3>Promote safety, integrity and security.</h3>
      <p>
        We use the information we have to verify accounts and activity, combat
        harmful conduct, detect and prevent spam and other bad experiences,
        maintain the integrity of our Services, and promote safety and security.
      </p>
      <h3>Communicate with you.</h3>
      <p>
        We use the information we have to send you marketing communications,
        communicate with you about our Services, and let you know about our
        policies and terms. We also use your information to respond to you when
        you contact us.
      </p>
      <p>
        Because recognition of the{' '}
        <Link href="https://en.wikipedia.org/wiki/Do_Not_Track">
          Do Not Track HTTP header feature of your web browser
        </Link>{' '}
        is not standardized, the Services don`t recognize it for tracking
        purposes.
      </p>
      <h2>Third-Party Data Collection</h2>
      <p>
        Third parties may collect or receive certain information about you
        and/or your use of the Services to provide content, ads (including
        personalized ads), or functionality, or to measure and analyze ad
        performance, in or through the Services. These third parties include:
      </p>
      <ul>
        <li>
          <p>
            Cloudflare (
            <ExternalLink
              target="_blank"
              href="https://www.cloudflare.com/website-terms/"
            >
              Terms
            </ExternalLink>
            ,&nbsp;
            <ExternalLink
              target="_blank"
              href="https://www.cloudflare.com/privacypolicy/"
            >
              Privacy Policy
            </ExternalLink>
            )
          </p>
        </li>
        <li>
          <p>
            Vercel (
            <ExternalLink target="_blank" href="https://vercel.com/legal/terms">
              Terms
            </ExternalLink>
            ,&nbsp;
            <ExternalLink
              target="_blank"
              href="https://vercel.com/legal/privacy-policy"
            >
              Privacy Policy
            </ExternalLink>
            )
          </p>
        </li>
        <li>
          <p>
            The Graph (
            <ExternalLink
              target="_blank"
              href="https://thegraph.com/terms-of-service/"
            >
              Terms
            </ExternalLink>
            ,&nbsp;
            <ExternalLink target="_blank" href="https://thegraph.com/privacy/">
              Privacy Policy
            </ExternalLink>
            )
          </p>
        </li>
        <li>
          <p>
            ChainLink (
            <ExternalLink target="_blank" href="https://chain.link/terms">
              Terms
            </ExternalLink>
            ,&nbsp;
            <ExternalLink
              target="_blank"
              href="https://chain.link/privacy-policy"
            >
              Privacy Policy
            </ExternalLink>
            )
          </p>
        </li>
        <li>
          <p>
            Alchemy (
            <ExternalLink
              target="_blank"
              href="https://www.alchemy.com/policies/terms"
            >
              Terms
            </ExternalLink>
            ,&nbsp;
            <ExternalLink
              target="_blank"
              href="https://www.alchemy.com/policies/privacy-policy"
            >
              Privacy Policy
            </ExternalLink>
            )
          </p>
        </li>
        <li>
          <p>
            Coinbase (
            <ExternalLink
              target="_blank"
              href="https://www.coinbase.com/legal/user_agreement/united_states"
            >
              Terms
            </ExternalLink>
            ,&nbsp;
            <ExternalLink
              target="_blank"
              href="https://www.coinbase.com/legal/privacy"
            >
              Privacy Policy
            </ExternalLink>
            )
          </p>
        </li>
        <li>
          <p>
            WalletConnect (
            <ExternalLink
              target="_blank"
              href="https://walletconnect.com/terms"
            >
              Terms
            </ExternalLink>
            ,&nbsp;
            <ExternalLink
              target="_blank"
              href="https://walletconnect.com/privacy"
            >
              Privacy Policy
            </ExternalLink>
            )
          </p>
        </li>
        <li>
          <p>
            AWS (
            <ExternalLink
              target="_blank"
              href="https://aws.amazon.com/service-terms/"
            >
              Terms
            </ExternalLink>
            ,&nbsp;
            <ExternalLink
              target="_blank"
              href="https://aws.amazon.com/privacy/"
            >
              Privacy Policy
            </ExternalLink>
            )
          </p>
        </li>
      </ul>
      <h2>Retention</h2>
      <p>
        The Services may keep the information we gather about you for an
        indefinite length of time.
      </p>
      <p>
        To request that information collected about you be deleted, please
        contact us at the email provided in this policy. A valid request must
        include sufficient information to identify your personal data. Note that
        we cannot delete information stored on public cryptographic blockchains.
      </p>
      <h2>Sharing</h2>
      <p>
        The Services only share information about you with others as follows:{' '}
      </p>
      <ul>
        <li>
          <p>
            We employ other companies to perform functions on our behalf, such
            as service providers that assist in the administration of the
            Services and our advertising and marketing efforts, data analytics
            companies that help us target our offerings, and marketing partners.
            We may need to share your information with these companies. These
            partners may access this information so long as you have an account
            on the Services.
          </p>
        </li>
        <li>
          <p>
            We may also transfer your personal data to a third party as a result
            of a business combination, merger, asset sale, reorganization or
            similar transaction or to governmental authorities when we
            reasonably believe it is required by law or appropriate to respond
            to legal process.
          </p>
        </li>
        <li>
          <p>
            We will also share your information with third-party companies,
            organizations or individuals if we have a good faith belief that
            access, use, preservation or disclosure of your information is
            reasonably necessary to detect or protect against fraud or security
            issues, enforce our terms of use, meet any enforceable government
            request, defend against legal claims or protect against harm our
            legal rights or safety. In any such event, and to the extent legally
            permitted, we will notify you and, if there are material changes in
            relation to the processing of your data, give you an opportunity to
            consent to such changes. Any third party with whom we share your
            data with will be required to provide the same or equal protection
            of such data as stated in our Privacy Policy.
          </p>
        </li>
        <li>
          <p>
            To operate the Services, we share information about you as needed
            with our service providers, including financial institutions,
            accountants, auditors, lawyers, information technology consultants,
            advisors, and our affiliates. We only share information to the
            extent it is required to fulfill our obligations to you and to
            regulators, and to operate the Services. The information is only
            shared so long as you are have an account on the Services.
          </p>
        </li>
        <li>
          <p>
            We routinely share information with companies closely related to us
            - our “affiliates“ - for certain purposes under this policy. Our
            affiliates will be entitled to enjoy our rights under this Privacy
            Policy and we will be responsible for our affiliates` conduct
            related thereto.
          </p>
        </li>
        <li>
          <p>
            We may share information about you with US, state or international
            regulators, SEC, or FINRA where we believe doing so is required or
            appropriate to comply with any laws, regulations or other legal
            processes or law enforcement requests, such as court orders, search
            warrants, or subpoenas.
          </p>
        </li>
        <li>
          <p>
            The Services may contain links to third party websites and may
            redirect you to third party websites. These sites include, among
            others, service providers who have a relationship with the operator.
            Third party websites are not under our control, and we are not
            responsible for any third party websites, or the accuracy,
            sufficiency, correctness, reliability, veracity, completeness, or
            timeliness of their information, links, changes or updates. The
            inclusion or access to these websites does not imply an endorsement
            by the operator, or of the provider of such content or services, or
            of any third party website. Please be aware that when you enter a
            third party website, any information you provide, including
            financial information, is subject to the terms of use and privacy
            policy of that website.
          </p>
        </li>
      </ul>
      <h2>Security</h2>
      <p>
        We have put in place appropriate security measures to prevent your
        personal data from being accidentally lost, used or accessed in an
        unauthorized way, altered or disclosed. In addition, we limit access to
        your personal data to those employees, agents, contractors and other
        third parties who have a business need to know. They will only process
        your personal data on our instructions and they are subject to a duty of
        confidentiality.
      </p>
      <p>
        We have put in place procedures to deal with any suspected personal data
        breach and will notify you and any applicable regulator of a breach
        where we are legally required to do so.
      </p>
      <h2>Contact</h2>
      <p>
        If you have comments or questions about the privacy policies of the
        Services, contact origamifi@proton.me.
      </p>
      <h2>Changes</h2>
      <p>
        The Services may change their privacy policy at any time. Check this
        page for the latest.
      </p>
    </PageContainer>
  );
}

const PageContainer = styled.div`
  padding: 0 2rem;
  padding-bottom: 1.5rem;
`;

const H1 = styled.h1`
  line-height: 3rem;
`;

const DocDate = styled.p`
  margin-top: -1.5rem;
  margin-bottom: 2rem;
`;

const ExternalLink = styled.a`
  color: ${({ theme }) => theme.colors.greyMid};
  font-size: 0.9rem;
  font-weight: bold;
  text-decoration: underline;
  filter: brightness(1.3);
  transition: color 300ms ease;
  &:hover {
    color: ${({ theme }) => theme.colors.white};
  }
`;
