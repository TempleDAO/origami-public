import { GMX_URL, ORIGAMI_URL, PRIVACY_POLICY_URL } from '@/urls';
import styled from 'styled-components';
import { Link } from '@/components/commons/Link';
import { AppRoutes } from '@/app-routes';

export function Page() {
  return (
    <PageContainer>
      <H1>Origami Finance Terms of Service</H1>
      <DocDate>Last updated: June 30, 2023</DocDate>
      <h2>Scope</h2>
      <p>
        These terms, and the accompanying privacy policy at&nbsp;
        <Link href={AppRoutes.PrivacyPolicy}> {PRIVACY_POLICY_URL}</Link>, which
        is incorporated into and a part of these terms, govern the use of the
        Origami Finance website at{' '}
        <Link href={AppRoutes.Index}>{ORIGAMI_URL}</Link> and the associated
        tools and services.
      </p>
      <p>
        Collectively, the website and the associated tools and services are
        referred to as the “<b>Services</b>“ in these terms. The Services do not
        include outside websites or platforms which may be linked or
        interconnected to the Services. Such outside platforms may have their
        own terms of service, which control for all transactions on such
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
        <b>
          <i>
            The operator is not responsible for any transactions on other
            platforms and disclaims all liability for such transactions.
          </i>
        </b>
      </p>
      <p>
        These terms include important provisions governing your use of the
        Services.&nbsp;
        <b>
          These provisions affect such matters as your right to use the
          Services, actions you are prohibited from taking with respect to the
          Services, disclaimers regarding liability, and your waiver of the
          right to bring a suit in a court of law and to a jury trial.
        </b>
        Before using the Services, make sure that you read and understand all of
        these terms and the accompanying privacy policy at
        <Link href={AppRoutes.PrivacyPolicy}> {PRIVACY_POLICY_URL}</Link>.
      </p>
      <p>
        Origami Foundation operates the Services. It and its affiliates are
        referred to in this document as the “operator,“ “we,“ or “us.“
      </p>
      <h2>Important Terms</h2>
      <p>
        These terms include a number of especially important provisions that
        affect your rights and responsibilities, such as the disclaimers
        in&nbsp;
        <b>Disclaimers</b>, limits on the operator`s legal liability to you
        in&nbsp;
        <b>Limits on Liability</b>, your agreement to reimburse the operator for
        problems caused by your misuse of the Services in&nbsp;
        <b>Your Responsibility</b>, and an agreement about how to resolve
        disputes in <b>Disputes.</b>
      </p>
      <p>
        Using the Services may require that you pay a fee to other users of the
        Services (such as merchants) or to the operator. Using the Services may
        also require that you pay a fee to parties other than users or the
        operator, such as gas charges on the blockchain to perform a
        transaction.&nbsp;
        <b>
          You acknowledge and agree that the operator has no control over any
          such transactions, the method of payment of such transactions or any
          actual payments of transactions.
        </b>
        &nbsp; Accordingly, you must ensure that you have a sufficient balance
        of the applicable cryptocurrency tokens stored at your
        protocol-compatible wallet address to complete any transaction on the
        blockchain or Services before initiating such transaction.
      </p>
      <h2>Your Permission to Use the Services</h2>
      <p>
        Subject to these terms, the operator gives you permission to use the
        Services. You can`t transfer your permission to anyone else. Others need
        to agree to these terms for themselves to use the Services.
      </p>
      <h2>Conditions for Use of the Services</h2>
      <p>
        Your permission to use the Services is subject to the following
        conditions:
      </p>
      <ol>
        <li>
          <p>You must be at least eighteen years old.</p>
        </li>
        <li>
          <p>
            You may no longer use the Services if the operator tells you that
            you may not.
          </p>
        </li>
        <li>
          <p>
            You must follow <b>Acceptable Use</b> and <b>Content Standards.</b>
          </p>
        </li>
      </ol>
      <h2>Acceptable Use</h2>
      <ol>
        <li>
          <p>
            <b>
              You may not use the Services if you are located in, a resident of,
              incorporated in, or have a registered agent in, the United States.
            </b>
          </p>
        </li>
        <li>
          <p>
            <b>You may not break the law using the Services.</b> If we determine
            that you have broken the law, we will revoke your access.
          </p>
        </li>
        <li>
          <p>
            You may not use or try to use anyone else`s account on the Services
            (or to connect with anyone else`s wallet) without their specific
            permission.
          </p>
        </li>
        <li>
          <p>
            You may not buy, sell, or otherwise trade usernames or other unique
            user or account identifiers on the Services.
          </p>
        </li>
        <li>
          <p>
            You may not make publicly available the personal information of
            other people using the Services.
          </p>
        </li>
        <li>
          <p>
            You may not send advertisements, chain letters, or other
            solicitations through the Services, or use the Services to gather
            addresses for distribution lists (except to the extent expressly
            provided by the functionality of the Services).
          </p>
        </li>
        <li>
          <p>
            You may not falsely imply that you`re affiliated with or endorsed by
            the operator.
          </p>
        </li>
        <li>
          <p>
            You may not remove any marks showing proprietary ownership from
            materials you download from the Services.
          </p>
        </li>
        <li>
          <p>
            You may not disable, avoid, or circumvent any security or access
            restrictions of the Services.
          </p>
        </li>
        <li>
          <p>
            You may not strain infrastructure of the Services with an
            unreasonable volume of requests, or requests designed to impose an
            unreasonable load on information systems the operator uses to
            provide the Services.
          </p>
        </li>
        <li>
          <p>
            You may not “screen scrape“ or otherwise use any automated means to
            access the Services or collect any information from the services,
            except to index the public-facing portions of the Services for a
            search engine.
          </p>
        </li>
        <li>
          <p>You may not impersonate others through the Services.</p>
        </li>
        <li>
          <p>
            You may not reverse engineer or “decompile“ any of the Services.
          </p>
        </li>
        <li>
          <p>
            You may not use a modified device to use the Services if the
            modification is contrary to the manufacturer`s software or hardware
            guidelines, including disabling hardware or software
            controls-sometimes referred to as “jail breaking.“
          </p>
        </li>
        <li>
          <p>
            You may not encourage or help anyone in violation of these terms.
          </p>
        </li>
      </ol>
      <h2>Enforcement</h2>
      <ol>
        <li>
          <p>
            The operator may investigate and prosecute violations of these terms
            to the fullest legal extent. The operator may notify and cooperate
            with law enforcement authorities in prosecuting violations of the
            law and these terms.
          </p>
        </li>
        <li>
          <p>
            The operator reserves the right to change, redact, and delete
            content on the Services for any reason. If you believe someone has
            submitted content to the Services in violation of these terms,
            contact the operator immediately. See <b>Contact.</b>
          </p>
        </li>
        <li>
          <p>
            The operator may, at any time and in its sole discretion, refuse any
            transaction, including any purchase, sale, or transfer request
            submitted via the Services, impose limits, or impose any other
            conditions or restrictions upon your use of the Services, without
            prior notice. The operator may also make the Services unavailable at
            any time, in its sole discretion.
          </p>
        </li>
      </ol>
      <h2>Your Information</h2>
      <p>You agree to:</p>
      <ol>
        <li>
          <p>
            Provide accurate, current and complete information about you if
            requested by any registration or subscription forms on the Services
            or otherwise requested by the operator;
          </p>
        </li>
        <li>
          <p>Maintain the security of your password and identification;</p>
        </li>
        <li>
          <p>
            Maintain and promptly update any information you provide to the
            operator, to keep it accurate, current and complete;
          </p>
        </li>
        <li>
          <p>
            Promptly notify the operator regarding any material changes to
            information or circumstances that could affect your eligibility to
            continue to use the Services or the terms on which you use the
            Services; and
          </p>
        </li>
        <li>
          <p>
            Be fully responsible for all use of your account on the Services and
            for any actions that take place using your account.
          </p>
        </li>
      </ol>
      <h2>Third Party Service Providers</h2>
      <p>
        To provide the Services, the operator may use the following service
        providers. You authorize us to share your information with these and
        other service providers as necessary for the provision of the Services.
        You authorize these service providers and their affiliates and service
        providers to use, disclose and retain your personal data in connection
        with these terms and the provision of the Services and as required by
        law. As a condition of the use of the Services, you agree to each of the
        agreements listed after each service provider.
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
      <h2>Our Content</h2>
      <ol>
        <li>
          <p>
            Unless otherwise stated, the operator and/or its licensors own the
            intellectual property rights for all material in the Services.
            Certain images or videos appearing on the Services may belong to
            third parties, in which case the operator is using such images as a
            fair and permissible use and/or with the consent of the copyright
            holder. All intellectual property rights are reserved.
          </p>
        </li>
        <li>
          <p>
            You may view and/or content in the Services for your own personal
            use subject to restrictions set in these terms and conditions.
          </p>
        </li>
        <li>
          <p>
            You may not republish, sell, rent, sub-license, reproduce,
            duplicate, or copy content from the Services, except with regard to
            your own content, or content to which you hold a suitably permissive
            license.
          </p>
        </li>
        <li>
          <p>
            You may not redistribute content from the services unless such
            content is specifically designated for redistribution.
          </p>
        </li>
        <li>
          <p>
            Nothing in these terms confers any license to any intellectual
            property rights, except as explicitly stated.
          </p>
        </li>
      </ol>
      <h2>Your Responsibility</h2>
      <p>
        You agree to reimburse the operator for all the costs of legal claims by
        others related to your breach of these terms, or breach of these terms
        by others using your account. Both you and the operator agree to notify
        the other side of any legal claims you might have to reimburse the
        operator for as soon as possible. If the operator fails to notify you of
        a legal claim promptly, you won`t have to reimburse the operator for
        costs that you could have defended against or lessened with prompt
        notice. You agree to allow the operator to take over investigation,
        defense, and settlement of legal claims you would have to reimburse the
        operator for, and to cooperate with those efforts. The operator agrees
        not to enter any settlement that admits you were at fault or requires
        you to do anything without your permission.
      </p>
      <h2>Disclaimers</h2>
      <ol>
        <li>
          <p>
            <b>You accept all risk of using the Services and their content.</b>
            &nbsp; As far as the law allows, the operator provides the Services
            and its content “as is,“ without any warranty whatsoever. The
            operator expressly disclaims, and you expressly waive, any
            representations, conditions or warranties of any kind, including,
            without limitation, the implied or legal warranties and conditions
            of merchantability, merchantable quality, quality or fitness for a
            particular purpose, title, security, availability, reliability,
            accuracy, quiet enjoyment and non-infringement of third party
            rights.
          </p>
        </li>
        <li>
          <p>
            <b>
              You confirm that you accept all risk associated your personal
              financial, cryptocurrency, and other crypto asset holdings,
              staking, and transfers.
            </b>
            You agree and acknowledge that the operator is not responsible or
            liable for any loss, harm, or damage, of any kind, related to or
            arising from your use of the Services, or arising from disclosure of
            your personal wallet “key,“&nbsp;
            <b>
              even if such loss may be attributed to an error or “bug“ in the
              Services.
            </b>
          </p>
        </li>
        <li>
          <p>
            We do not warrant that the Services will be compatible with your
            mobile device or carrier. Your use of the Services may be subject to
            the terms of your agreements with your mobile device manufacturer or
            your carrier.
          </p>
        </li>
        <li>
          <p>
            At any time, your access to your tokens or other cryptocurrency
            assets may be suspended or terminated or there may be a delay in
            your access or use which may result in your tokens or other
            cryptocurrency assets diminishing in value or you being unable to
            complete a smart contract.
          </p>
        </li>
        <li>
          <p>
            You accept all risks associated with the use of the Services to
            conduct cryptocurrency transactions, including, but not limited to,
            in connection with the failure of hardware, software, internet
            connections, and failures related to any supported network.
          </p>
        </li>
        <li>
          <p>
            The Services may be suspended or terminated for any or no reason,
            which may limit your access to your cryptocurrency assets.
          </p>
        </li>
        <li>
          <p>
            The website may hyperlink to and integrate websites and services run
            by others. The operator does not make any warranty about services
            run by others, or content they may provide. Use of services run by
            others may be governed by other terms between you and the one
            running service.
          </p>
        </li>
        <li>
          <p>
            You agree that you understand the inherent risks associated with
            cryptographic systems, including hacking risks and future
            technological development.
          </p>
        </li>
        <li>
          <p>
            You agree that you have an understanding of the usage and
            intricacies of native cryptographic tokens.&nbsp;
            <b>
              You acknowledge and understand that with regard to any
              cryptographic tokens “stored“ in a wallet to which you have
              custody, you alone are responsible for securing your private
              key(s).
            </b>
            &nbsp; We do not have access to your private key(s). Losing control
            of your private key(s) will permanently and irreversibly deny you
            access to blockchain resources and your blockchain wallet.
          </p>
        </li>
        <li>
          <p>
            You agree that with regard to any cryptographic tokens or other
            assets stored on resources hosted by the operator, the operator is
            not liable to you for any loss, failure, or unavailability of any
            kind, of such tokens or assets, for any reason.
          </p>
        </li>
        <li>
          <p>
            Regardless of anything to the contrary in these terms, nothing in
            these terms is a waiver, and we will not assert there has been a
            waiver, that would not be permissible under Section 14 of the
            Securities Act of 1933, Section 29(a) of the Securities Exchange Act
            of 1934, or any other applicable provision of federal and state
            securities laws.
          </p>
        </li>
        <li>
          <p>
            You acknowledge that the operator and its affiliates do not provide
            investment advice or a recommendation of securities or investments.
            You should always obtain independent investment and tax advice from
            your professional advisers before making any investment decisions.
          </p>
        </li>
        <li>
          <p>
            The information and services provided on the Services are not
            provided to, and may not be used by, any person or entity in any
            jurisdiction where the provision or use thereof would be contrary to
            applicable laws, rules or regulations of any governmental authority
            or where the operator is not authorized to provide such information
            or services. Some products and services described on the Services
            may not be available in all jurisdictions or to all clients.
          </p>
        </li>
        <li>
          <p>
            You acknowledge that you are not relying on the operator or any of
            its affiliates, officers, directors, partners, agents or employees
            in making an investment decision. Always consider seeking the advice
            of a qualified professional before making decisions regarding your
            business and/or investments. The operator does not endorse any
            investments and shall not be responsible in any way for any
            transactions you enter into with other users. You agree that the
            operator and its affiliates, officers, directors, partners, agents
            or employees will not be liable for any loss or damages of any sort
            incurred as a result of any interactions between you and other
            users.
          </p>
        </li>
        <li>
          <p>
            It is your responsibility to determine what, if any taxes may apply
            to the transactions you complete under the Services and it is your
            responsibility to report and remit the appropriate tax to the
            relevant taxing authorities. You agree that the operator is not
            responsible for determining whether taxes apply to the exchanges
            made under the Services.
          </p>
        </li>
      </ol>
      <h2>Limits on Liability / Indemnification</h2>
      <ol>
        <li>
          <p>
            <b>
              As far as the law allows, neither you nor the operator will not be
              liable to the other for any: (1) financial losses; (2) loss of
              use, data, business or profits; or (3) indirect, special,
              consequential, exemplary, punitive, or any other damages arising
              out of or relating to the Services or these Terms of Service.
            </b>
          </p>
        </li>
        <li>
          <p>
            Both you and the operator acknowledge that the limitations of
            liability in this section are material provisions of these Terms of
            Service, and that absent those limitations of liability, one or both
            of the parties would have declined to enter into the Terms of
            Service on the economic and other terms stated in it.
          </p>
        </li>
        <li>
          <p>
            <b>
              To the extent not expressly prohibited by law, both you and the
              operator knowingly, voluntarily, intentionally, permanently, and
              irrevocably:
            </b>
          </p>
          <ol type="a">
            <li>
              <p>
                AGREE that the rights and obligations of both you and the
                operator that arise out of or relate to the Services, or any
                transaction or relationship resulting from the Services or these
                Terms of Service, are to be defined solely under the law of
                contract in accordance with the express provisions of these
                Terms of Service; and
              </p>
            </li>
            <li>
              <p>
                WAIVE any such obligations allegedly owed by you or the operator
                that are not expressly stated in these Terms of Service, whether
                those obligations are alleged to arise in (for example)
                quasi-contract; quantum meruit; unjust enrichment; promissory
                estoppel; tort; strict liability; by law (including for example
                any constitution, statute, or regulation); or otherwise.
              </p>
            </li>
          </ol>
        </li>
        <li>
          <p>
            You and the operator specifically agree that each limitation of
            liability in this section is to apply:
          </p>
          <ol type="a">
            <li>
              <p>
                to both you and the operator, and to the affiliates, agents, and
                associated individuals of both you and the operator;
              </p>
            </li>
            <li>
              <p>
                to all claims for damages or other monetary relief, whether
                alleged to arise in contract, tort (including for example
                negligence, gross negligence, or willful misconduct), or
                otherwise;
              </p>
            </li>
            <li>
              <p>
                regardless whether the damages are alleged to arise in contract,
                negligence, gross negligence, other tort, willful misconduct, or
                otherwise;
              </p>
            </li>
            <li>
              <p>
                even if the allegedly-liable party was advised, knew, or had
                reason to know of the possibility of excluded damages and/or of
                damages in excess of the relevant damages cap, if any; and
              </p>
            </li>
            <li>
              <p>
                even if one or more limited remedies fail of their respective
                essential purposes.
              </p>
            </li>
          </ol>
        </li>
        <li>
          <p>
            <b>
              Except as expressly stated otherwise in the Agreement: The
              cumulative total liability of both you and the operator, for any
              and all breaches of these Terms of Service, is not to exceed one
              hundred US Dollars ($100.00 USD) OR the amount paid by you to the
              operator as fees for the use of the Services, whichever is
              smaller.
            </b>
          </p>
        </li>
        <li>
          <p>
            Both you and the operator expressly agree not to seek damages in
            excess of any applicable limitation of liability stated in these
            Terms of Service.
          </p>
        </li>
        <li>
          <p>
            Both you and the operator acknowledge that some jurisdictions might
            not permit limitation or exclusion of remedies under some
            circumstances, in which case some or all of the limitations of
            liability stated in this section might not apply; this sentence,
            though, is not to be taken as a concession that any particular
            limitation or exclusion should not apply.
          </p>
        </li>
        <li>
          <p>
            You agree that you will defend, indemnify and hold harmless the
            operator, its affiliates, licensors and service providers, and its
            and their respective officers, directors, employees, contractors,
            agents, licensors, suppliers, successors and assigns from and
            against any claims, liabilities, damages, judgments, awards, losses,
            costs, expenses or fees (including reasonable attorneys` fees)
            arising out of or relating to your violation of these Terms or your
            use of the Services.
          </p>
        </li>
      </ol>
      <h2>Termination</h2>
      <ol>
        <li>
          <p>
            Either you or the operator may end this agreement at any time. When
            this agreement ends, your permission to use the Services also ends.
          </p>
        </li>
        <li>
          <p>
            If you violate any provision of this agreement for any reason, this
            agreement will automatically terminate and you must cease and desist
            from any further use of the Services.
          </p>
        </li>
        <li>
          <p>
            The following sections continue after this agreement ends:&nbsp;
            <b>
              Your Content, Feedback, Your Responsibility, Disclaimers, Limits
              on Liability, and General Terms.
            </b>
          </p>
        </li>
      </ol>
      <h2>Disputes</h2>
      <ol>
        <li>
          <p>
            The law of Cayman Islands will govern these terms and all legal
            proceedings related to these terms or your use of the Services.
          </p>
        </li>
        <li>
          <p>
            We both agree that all disputes related to the Services under these
            terms will be heard by arbitration. The arbitration will be in
            English, heard by one arbitrator, and conducted by JAMS.
          </p>
        </li>
        <li>
          <p>
            The arbitration will be conducted pursuant JAMS` International
            Arbitration Rules, and in accordance with the Expedited Procedures
            in those rules, except as modified by these terms. The JAMS rules
            are available at https://www.jamsadr.com/.
          </p>
        </li>
        <li>
          <p>
            The arbitrator`s judgment will be final and enforceable in any court
            of competent jurisdiction.
          </p>
        </li>
        <li>
          <p>
            The seat of the arbitration will be Cayman Islands; but the
            arbitration will be conducted remotely to the extent permitted by
            the arbitration rules in effect.
          </p>
        </li>
        <li>
          <p>
            We both agree to maintain the confidential nature of any arbitration
            proceeding and any award, except as may be necessary to prepare for
            or conduct any arbitration hearing.
          </p>
        </li>
        <li>
          <p>
            As a limited exception to the requirement for arbitration, both
            sides retain the right to seek injunctive or other equitable relief
            from a court to prevent (or enjoin) the infringement or
            misappropriation of our intellectual property rights.
          </p>
        </li>
        <li>
          <p>
            If, for any reason, a dispute is heard in a court of law, both sides
            agree to bring any proceedings related to this agreement (other than
            the enforcement of a judgment) only in courts of competent
            jurisdiction in the location of the operator`s incorporation.
          </p>
        </li>
        <li>
          <p>
            Neither you nor the operator will object to jurisdiction, forum, or
            venue in those courts.
          </p>
        </li>
        <li>
          <p>
            <b>
              Both sides waive their rights to trial by jury, and agree to bring
              any legal claims related to this agreement as individuals, not as
              part of a class action or other representative proceeding.
            </b>
          </p>
        </li>
      </ol>
      <h2>General Terms</h2>
      <ol>
        <li>
          <p>
            If a section of these terms is unenforceable as written, but could
            be changed to make it enforceable, that section should be changed to
            the minimum extent necessary to make it enforceable. Otherwise, that
            section should be removed, and the others should be enforced as
            written.
          </p>
        </li>
        <li>
          <p>
            You may not assign this agreement. The operator may assign this
            agreement to any affiliate of the operator, any other company that
            obtains control of the operator, or any other company that buys
            assets of the operator related to the Services. Any attempt to
            assign against these terms has no legal effect.
          </p>
        </li>
        <li>
          <p>
            Neither the exercise of any right under this agreement, nor waiver
            of any breach of this agreement, waives any other breach of this
            agreement.
          </p>
        </li>
        <li>
          <p>
            These terms, plus the terms on any Services incorporating them by
            reference, are all the terms of agreement between you and the
            operator about use of the Services. This agreement entirely replaces
            any other agreements about your use of the Services, written or not.
          </p>
        </li>
      </ol>
      <h2>Contact</h2>
      <ol>
        <li>
          <p>
            You may notify the operator under these terms, and send questions to
            the operator, using the contact information they provide.
          </p>
        </li>
        <li>
          <p>
            The operator may notify you under these terms using the e-mail
            address you provide for your account on the Services, or by posting
            a message to the homepage of the Services or your account page.
          </p>
        </li>
      </ol>
      <h2>Changes</h2>
      <ol>
        <li>
          <p>
            The operator may update the terms of service for the Services. The
            operator will post all updates to the Services. The operator may
            also announce updates with special messages or alerts on the
            Services.
          </p>
        </li>
        <li>
          <p>
            Once you get notice of an update to these terms, you must agree to
            the new terms in order to keep using the Services.
          </p>
        </li>
      </ol>
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
