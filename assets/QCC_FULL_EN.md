# QCC Whitepaper v2.0 — Contents

- Chapter 1 What Is QCC
  - 1.1 The Essential Definition of QCC
  - 1.2 QCC's First Principle
  - 1.3 QCC Is a Blockchain Operating System
  - 1.4 Core Concepts Mapped
  - 1.5 QCC's Definition of Decentralization
  - 1.6 QCC's Unified View of Transactions
  - 1.7 QCC's Ecosystem Goal
- Chapter 2 QCC's Technical Foundation and System Architecture
  - 2.1 Every On-Chain Action Is a Transaction
  - 2.2 The Container Chain
    - 2.2.1 How a Container's Hash Is Built
  - 2.3 Consensus: Execution-Layer Hash Consistency, No Voting
  - 2.4 The Producer Cluster
    - 2.4.1 Why a Producer Cluster
    - 2.4.2 Conditions for Joining the Cluster
    - 2.4.3 Producer State Machine and Ordering
    - 2.4.4 Time Slots and Rotation
    - 2.4.5 Stake Lock and Exit
    - 2.4.6 Transaction Routing and Caching
    - 2.4.7 Scale
    - 2.4.8 Genesis Start
  - 2.5 Network and Synchronization
    - 2.5.1 Two Network Layers
    - 2.5.2 IPv6 First
    - 2.5.3 Synchronization Principles
    - 2.5.4 The Line Between Full Replay and Snapshots
  - 2.6 State Machine Architecture
  - 2.7 The Rule Set
    - 2.7.1 The Protocol Freeze Principle
  - 2.8 A Unified Model for Assets and Data
  - 2.9 The Byte Protocol
  - 2.10 Post-Quantum Keys and the Account System
    - 2.10.1 Signature Algorithm: ML-DSA-87
    - 2.10.2 Key Derivation: Mnemonic + Payment Password, Two Factors
    - 2.10.3 A Leaked Mnemonic No Longer Means Lost Assets
    - 2.10.4 Address Format
    - 2.10.5 Multisig: Joint Signing
    - 2.10.6 The Transaction Signing String
    - 2.10.7 Signature Vault and Public-Key Vault
    - 2.10.8 Security Layers of the Account System
- Chapter 3 What QCC Can Do
  - 3.1 QCC's Two Main Directions
  - 3.1.1 Financial Infrastructure
  - 3.1.2 Trusted Data Service Infrastructure
  - 3.2 Financial Infrastructure: What QCC Can Serve
  - 3.2.1 Basic Transfers and On-Chain Payments
  - 3.2.2 Stablecoins and Asset Tokens
  - 3.2.3 Decentralized Trading and Rule-Based Asset Markets
  - 3.2.4 Inheritance Transactions and Decentralized Trusts
  - 3.2.5 Regional and Global Coordination Ledger Networks
  - 3.2.6 Merchant Payments, Clearing and Callback Networks
  - 3.2.7 Supply-Chain Finance, On-Chain Bills and Product Traceability
  - 3.2.8 Financial Extensibility as an On-Chain Operating System
  - 3.3 Trusted Data Service Infrastructure: What QCC Can Serve
    - 3.3.1 Entity Data On Chain and Trusted Notarization
    - 3.3.2 Enterprise-Grade Auditable Records and On-Chain Database Capability
    - 3.3.3 Judicial Notarization, Arbitration and Trusted Evidence
    - 3.3.4 AI Trusted Data, Model Traces and AI-Agent Collaboration
    - 3.3.5 Social, Messaging, Mini-Programs and Content Publishing
    - 3.3.6 Application Publishing, the Developer Ecosystem and Industry-Level On-Chain Services
    - 3.3.7 Next-Generation Internet Security
    - 3.3.8 Independently Verifiable Applications for Society and Industry
    - 3.3.9 Extension After the Freeze: Extension Protocol as Subchain Genesis
    - 3.3.10 Trusted Data Extensibility as an On-Chain Operating System
- Chapter 4 The QCC Native Coin and On-Chain Economic Rules
  - 4.1 Introducing the QCC Native Coin
  - 4.2 A Unified Cost Carrier: The Native Coin and the Transaction Model
  - 4.3 Supply, Precision and Unified Numeric Boundaries
  - 4.4 Gas and System Fund Pools
    - 4.4.1 No Asset Ever Disappears
    - 4.4.2 Gas Distribution
    - 4.4.3 Fees Only Go Down
  - 4.5 The Staking System
  - 4.6 The Native Coin's Many Roles
- Chapter 5 The Genesis Container — QCC's Height-Zero Declaration
  - 5.1 Definition and Unique Status of the Genesis Container
  - 5.2 Technical Particularities
  - 5.3 The One and Only Union of Three
  - 5.4 What the Genesis Container Holds
  - 5.5 Historical and Civilizational Significance
  - 5.6 The Founder's Legacy and Encrypted Messages
- Chapter 6 QCC's Long-Term Order and Ecosystem Path
  - 6.1 QCC's Positioning as Public Chain and Operating System Infrastructure
  - 6.2 Rules Over Power
  - 6.3 Ecosystem Path: Asset Independence, Wolf-Pack Collaboration
  - 6.4 Open-Source and Intellectual Property Path
  - 6.5 The QCC Native Coin and Long-Term Operating Order
  - 6.6 Long-Term Goal: From an Established Protocol to Global Trusted Infrastructure
- Chapter 7 Test Network and Engineering Validation
  - 7.1 This Is Not a Slide-Deck Project
  - 7.2 Testnet Topology
  - 7.3 Transaction Performance
  - 7.4 Trusted Data Notarization Performance
  - 7.5 Key Feature Validation
  - 7.6 From Testnet to Mainnet: What Remains
- Conclusion

---

# Chapter 1 What Is QCC

---

## 1.1 The Essential Definition of QCC

QCC is a **blockchain operating system for trusted ledgers and trusted data**.

It is built on **trusted on-chain byte data**, centered on **rule-driven execution**, and aimed at **the unified circulation of assets and data**. It plays two roles at once: as a **value network**, it handles the issuance, transfer and ownership of assets; as a **data network**, it handles the trusted recording, structured publication and long-term preservation of real-world information.

QCC fundamentally rebuilds the relationship between value and data: it does not treat asset speculation as the end point (although speculation is possible), but starts from **supporting complex real-world business logic**.

> QCC is not a transfer-only chain, not a single-purpose notarization chain, and not a smart contract platform. QCC's goal is not for an official team to build every application, but to provide the underlying on-chain runtime for third-party developers, enterprises and institutions.

---

## 1.2 QCC's First Principle

The first principle of blockchain is not issuing coins — it is **immutability**.

The essential value of immutability should not serve transfer records alone. It should extend further to:

- **Trusted data**: giving any byte data an immutable, trusted origin
- **Trusted ledgers**: making every change of assets, ownership and rules traceable
- **Verifiable actions**: giving on-chain operations explicit semantics and verifiable consequences
- **Auditable rules**: making business rules public, transparent and confirmable
- **Traceable state**: making the system state at any moment recoverable — anyone can replay it completely from height 0

QCC advances along exactly this first principle — extending immutability from a "transfer ledger" to a "trusted byte network".

More precisely, QCC is a system in which **all rules and all data are replayable**: the rule set and data used for replay are one and the same, not a collection of rules from successive forks. Any ordinary computer that obtains the full container data plus the signature vault and public-key vault can independently replay, from height 0, a state identical to the whole network, without relying on any external or official snapshot.

---

## 1.3 QCC Is a Blockchain Operating System

If you have used iOS, you already understand QCC's system structure.

iOS provides a unified runtime for applications on mobile devices; QCC provides a unified trusted runtime for on-chain business. The system logic of the two is highly isomorphic — not as a metaphor, but as a real design correspondence.

| Dimension | iOS | QCC |
|------|-----|-----|
| **Positioning** | Mobile device operating system | Blockchain operating system |
| **First principle** | Device control and app runtime security | Immutability, extended to trusted data, trusted ledgers and trusted rules |
| **Native runtime unit** | App / process | Container |
| **Application carrier** | Each app is an independent unit | Each container is bound to a unique asset ID and is an independent unit |
| **Permission model** | Camera, photos, location, etc., requested by apps as needed | Freeze, mint, burn, whitelist, etc., declared at asset issuance |
| **Permission boundary** | One app having a permission does not grant it to others | One asset being freezable does not make other assets freezable |
| **Lifecycle** | Install, launch, foreground, background, suspend, terminate | Launched by a transaction, executed, put on chain; destroyed without going on chain if there is no data |
| **Isolation** | Apps isolated by default | Containers isolated by default — independent rule, asset and state boundaries |
| **Rule layers** | System frameworks / developer APIs | Genesis rules / system rules / asset rules / user rules / pledge rules |
| **Opening system capabilities** | Apple defines capabilities; developers call them within bounds | QCC defines the rule set; developers instantiate it through transactions |
| **Publishing applications** | Developers publish apps, subject to system rules | Developers publish assets and rules through on-chain transactions |
| **Permissionless** | Subject to App Store review | No real-name requirement, no manual approval — anyone can issue assets or deploy nodes |
| **Extension** | System version upgrades | The base protocol freezes at the first official release; extension protocols are fully stored on-chain as subchain genesis |
| **Ecosystem goal** | Let developers build countless apps around the system | Let developers build financial, notarization, AI, social and enterprise applications around containers |
| **End state** | The application foundation on the device | The foundation for trusted data, trusted ledgers and on-chain applications |

---

## 1.4 Core Concepts Mapped

Once you understand the system logic of iOS, every core design decision of QCC has an intuitive counterpart:

**Container = process** A container is a runtime execution unit. Each container is bound to a unique asset ID — a USDS container holds only USDS transactions. A container is launched by a transaction and is destroyed without going on chain if no data arrives within about 3 seconds; it is produced and put on chain only when there is data. Unlike Bitcoin or Ethereum, QCC therefore does not produce empty blocks on a fixed rhythm: **containers exist only when there is data, and the interval between containers is itself a real signal of network activity.**

**Block = thread / data boundary** Blocks exist inside containers and organize the concrete transactions and data fragments in a container, handling ordering, segmentation and local indexing. The real hash chain is formed **between containers**: containers are linked into a single chain in the order they actually occur, and adjacent containers may hold different assets (QCC → USDS → RULE interleaved).

**Native containers = system privileges** The RULE container and the DATA container are the only two native containers. They cannot be created anew or minted, and are equivalent to system-level privileges. Asset containers are open to everyone and come in two kinds: stablecoins and tokens.

**Rule = permission** A rule is not globally shared code, but a permission instance that takes effect with an asset. Asset A can be freezable while asset B is not; asset A can be mintable while asset B has a fixed supply. These capabilities are declared by the issuer at issuance and cannot be added afterwards.

**Rule set = the replacement for smart contracts** Traditional smart contracts deploy arbitrary code on chain to be interpreted by a virtual machine, with blurry boundaries that are hard to audit. QCC has no contract mechanism at all: the system predefines a rule set, developers instantiate rules through transactions, and rules take effect independently within asset boundaries. The rule set can be understood as "system-level rules frozen once", covering more than 90% of commonly used on-chain rules.

> **QCC natively refuses "writing code" on chain for business logic, and advocates "configuring rules" on chain.**

**Transaction = system call (syscall)** Every on-chain action is uniformly expressed as a transaction — not just transfers, but also rule publication, asset creation, data notarization, permission changes, staking, address lifecycle management, and even manual operations themselves. Transactions are the **unified action language** of the on-chain world, like system calls in an operating system.

**Subchain = an independent system bootstrapped by QCC** Once QCC's base layer is frozen, new capabilities are no longer added by modifying the base protocol, but by "storing an extension protocol fully on chain": an extension protocol (rules, byte protocol, execution consistency algorithm) is published to QCC as a full byte-level notarization, equivalent to the genesis block of a new chain. Nodes of the new system read the protocol from QCC to start up, execute independently and compare execution-layer hashes. QCC provides an immutable, verifiable and trustworthy bootstrap protocol; the subchain produces its own data and does not need to return to QCC containers.

---

## 1.5 QCC's Definition of Decentralization

QCC's decentralization is not a slogan but a fact guaranteed directly by the protocol structure:

- **Permissionless**: anyone can deploy a node, sync the full chain and run a super node. There are only two entry conditions — the address meets the QCC standard and is not a duplicate, and the execution-layer hash matches the network. No entity's approval is required.
- **No admin**: QCC has no admin backend anywhere, no administrative address, and no privileged channel that can manually tune parameters, freeze other people's assets or modify rules.
- **Production rights are determined by stake and rules**: any node that stakes 10,000 QCC can join the producer cluster and take turns producing containers according to replayable on-chain rules. Producers are not elected "leaders" but producers rotating in a deterministic order.
- **Rules over power**: the base protocol is frozen at the first official release, and no one can modify it afterwards. Issuers' powers are likewise constrained by rules — for example, assets at a frozen address can only be burned after being frozen for 12 consecutive months, a period determined by consensus time that no one can shorten.

QCC's decentralization therefore means: **open participation, open development, open publication, open production — and no one can control it.**

---

## 1.6 QCC's Unified View of Transactions

What QCC calls a "transaction" is not a transfer in the narrow sense.

In QCC, any action that can be submitted to the ledger, form a trusted record, and cause a state change, a rule confirmation or a change of ownership is a unified transaction. A transfer is just one kind.

The following actions all enter the system as transactions in QCC:

- Peer-to-peer asset transfers
- Rule publication, update and instantiation
- Asset creation and definition
- Data notarization
- Staking, unstaking and node production eligibility
- Permission changes and address lifecycle management
- System-level rule invocation

Through unified transactions, QCC brings trusted data in the broad sense into a single ledger system. Even "manual operations" are transactions, equally queryable, auditable and replayable.

---

## 1.7 QCC's Ecosystem Goal

QCC is not responsible for building every application on behalf of developers. QCC is responsible for providing a minimal, stable base protocol that never changes after it is frozen, so that third parties can build freely on top of containers:

- **Financial applications**: stablecoins, bills, clearing and settlement, institutional assets, inheritance and trusts
- **Notarization applications**: financial reports, contracts, vouchers, trusted records
- **Next-generation internet security**: decentralized accounts, storage, authentication and encrypted access
- **AI trusted ledgers**: AI behavior records, data provenance notarization
- **Enterprise business systems**: auditable business processes and ownership management

QCC's protocol core keeps a minimal implementation and does not pursue complex features; complex trust, yield and business products are built by third parties on top of the core primitives.

QCC's end state is to become **the foundation for trusted data, the foundation for trusted ledgers, and the foundation for third-party on-chain applications**.

---

## Chapter Summary

QCC is not a transfer chain, not a notarization chain, and not a smart contract platform.

QCC is a **blockchain operating system for trusted ledgers and trusted data** — containers are processes, blocks are data boundaries inside containers, rules are permissions, the rule set replaces smart contracts, and unified transactions are the system call language.

- Transactions define actions
- Containers carry objects and are produced only when there is data
- Blocks implement data boundaries inside containers
- Assets define ownership and permissions
- Business logic natively refuses "writing code" on chain and advocates "configuring rules"
- State machines drive execution; all rules and all data are replayable
- A minimal byte protocol replaces text protocols
- Security first: post-quantum signatures and rule boundaries
- Permissionless, no admin, and the base protocol freezes at the first official release

Together, these core abstractions form QCC's system ontology — a blockchain operating system born for complex real-world business logic.

---

# Chapter 2 QCC's Technical Foundation and System Architecture

## 2.1 Every On-Chain Action Is a Transaction

QCC does not define a "transaction" as a transfer in the narrow sense, but as the unified action language of the on-chain world.

In traditional blockchains, a transaction usually only represents assets flowing from one address to another. In QCC, any action that can enter the ledger, form a trusted record, cause a state change, trigger a rule confirmation or change ownership is uniformly expressed as a transaction. In QCC, therefore, all of the following are essentially transactions:

- Asset transfers
- Rule publication, update and instantiation
- Asset creation and parameter definition
- Data notarization and entity records
- Staking, unstaking and production eligibility
- Permission changes and address lifecycle management
- Developer, merchant and business-level on-chain submissions

QCC adopts a unified transaction model because an on-chain system that is to carry complex business cannot invent an entirely different base object for every kind of action. QCC converges different business semantics into unified transactions, and then distinguishes their business consequences by transaction type, asset domain (assetId), rule context, state machine path, Gas logic, and signature and permission boundaries.

In other words, a QCC "transaction" is not merely a payment action, but a standardized submission that passes signature verification, pays Gas, enters a container, takes part in confirmation and is written into the trusted ledger.

The unified view of transactions brings four core benefits:

- **Unified verification**: every on-chain action goes through the same signature, Gas and validity checks
- **Unified audit**: every key action enters the same ledger system
- **Unified extension**: new business capabilities require no rewrite of the base protocol paradigm
- **Unified understanding**: developers and nodes all build around the same basic action model

QCC exposes only 5 transaction entry APIs: `txm` (transactions), `rule` (rules), `data` (notarization), `mtxrule` (multisig rules) and `mutxbaseData` (multisig transactions). All traffic enters the producer cluster through them.

---

## 2.2 The Container Chain

QCC's core chain structure is not the traditional single-layer block model, but a chain of containers.

A container is the standard on-chain unit, the business carrier and the unit by which the network's hash chain advances. A container has a dual nature:

- From the business abstraction, a container is like a process — an on-chain runtime unit that independently carries assets, rules, data and state boundaries
- From the chain structure, a container is the object by which the main chain advances — the basic unit of confirmation, propagation, persistence, synchronization and hash linkage

Correspondingly, **blocks** in QCC are no longer the body of the main chain, but data boundary units inside containers that organize the concrete transactions and data fragments in a container.

The core organizing principle of the QCC container chain:

> **One container serves exactly one assetId asset domain.**

This brings three core benefits: asset-domain isolation, rule-domain isolation and state-domain isolation. Different assets and data businesses are never mixed; state updates, freezes, minting, indexing and auditing can all proceed independently around a single asset domain.

Containers are **data-driven**: when a transaction arrives, the container for that asset is launched and collects data for about 3 seconds; if there is data, it is executed and put on chain, otherwise it is destroyed without going on chain. There is only one chain: containers are linked into a hash chain in the order they actually occur, and adjacent containers may belong to different assets.

### 2.2.1 How a Container's Hash Is Built

A container's final on-chain hash is not generated in one step, but bound progressively in three stages.

**Stage 1: local seal**

Before entering chain-head allocation, the container completes its content seal locally, producing a digest representing the container's content (bodyHash) and a digest binding the container's identity (containHash).

【TBD: verify the stage-1 formula against the container class that contains `overSeal()`】

**Stage 2: chain-head allocation**

The chain-head manager (`PrevHashTrackChainManager`) is the single point of sequential advancement for the whole chain. It assigns three fields, in order, to the consensus voucher (TxConsensus) of each container waiting to go on chain:

```
height     // network-wide unique height
timestamp  // container time (assigned by the producer)
prevHash   // tailHash of the preceding container
```

The chain-head manager works as "single-task occupancy + waiting queue": only one container holds the chain head at any moment. Only after the balance state machine confirms successful execution does the chain head advance (height +1, prevHash updated to the new tailHash) and move on to the next container; if execution fails, the chain head does not advance and is released directly to the next container. This guarantees strict ordering and single-threaded advancement of the container chain.

**Stage 3: final binding (overSeal)**

After the chain-head fields are injected, the container performs its final binding and generates the official on-chain hash, tailHash. The tailHash is the source of the next container's prevHash.

【TBD: write the tailHash formula from the current `overSeal()` implementation (whether container time and the producer nodeId are included)】

The real hash relation of the container chain is `tailHash(N) → prevHash(N+1) → tailHash(N+1)`: the chain is formed at the container level, not the block level. The hash algorithm across the whole chain is **SHA3-256**, and the anchor hash of the genesis container also uses SHA3-256.

When a node restarts and recovers, the chain head's height and tailHash are read from the state snapshot — the same snapshot file as the account state, rule state and execution-layer hash chain head — so the three are strictly aligned. Containers are then replayed from snapshot height +1, with tailHash verifying chain continuity and executeHash verifying state consistency.

---

## 2.3 Consensus: Execution-Layer Hash Consistency, No Voting

QCC's consensus does not rely on voting, nor on any signature other than transaction signatures.

**Beyond ML-DSA-87 transaction signatures, QCC performs no signing and no voting.** Whether a container is valid is verified by execution-layer hash consistency:

- Each container produces an execution-layer hash (executeHash) after execution; executeHash advances container by container as a chain
- The producer's nodeId is bound into executeHash through the Gas reward account
- All nodes execute the same container and obtain the same executeHash — that is agreement; any node can recompute and verify independently

The only source of truth for consensus is the **container consensus voucher (TxConsensus)**: it is broadcast by the producer, and nodes that have executed that height can also forward it to any node. The voucher needs no signature and can be verified independently; after receiving a voucher, a node pulls the corresponding container over HTTP to complete synchronization.

**Handling malicious containers**: if a container's execution-layer hash does not match the network, the container is neither kept nor replayed — the execution layer rolls back, the execution layer and index layer coordinate to revert that height, it is treated as an empty slot, and the next producer produces a valid container. On mainnet, execution-layer inconsistency never causes the network to halt; a minority of nodes that isolate themselves because of their own errors simply reset and resync.

The significance of this mechanism: consensus is no longer a "vote" but a "deterministic check". There is no voting round that can be delayed, bought or censored.

---

## 2.4 The Producer Cluster

### 2.4.1 Why a Producer Cluster

In an open protocol, a single producer has a fatal flaw: **the producer can refuse to work** (a production-refusal attack). The producer cluster solves exactly this problem — if the current producer refuses to produce, the next producer takes over at a deterministic point in time.

At ultra-high production speeds, refusal is no longer possible; what remains is production security:

> **Production security = fast synchronization + execution-layer hash consistency verification.**

It must be stressed that QCC nodes are equal: at any moment there is only **one** producer, and all other nodes replay and sync with execution-layer consistency. The producer cluster only changes how production rights are handed over; it is not a "many nodes produce independently and then converge" model. There is no "leader" in QCC — only producers rotating in a deterministic order.

### 2.4.2 Conditions for Joining the Cluster

- **Stake**: at least **10,000 QCC** staked on chain (a fixed protocol value that never changes). Node servers hold no private keys; a nodeId's identity is the stake state of that address
- **Sync height**: a node more than 10 containers behind the latest network height leaves the producer cluster and returns to the sync network; it can rejoin only after catching up to within 5 containers

### 2.4.3 Producer State Machine and Ordering

The index layer has a built-in producer state machine that maintains a **total order** of all nodes with a stake of at least 10,000 QCC. The ordering is driven entirely by replayable on-chain events:

- **Heat score**: points are added for producing a valid container; no points are deducted for idling; points are deterministically deducted only when it was this node's turn but another node produced (and transactions were waiting during that time)
- **Registration time**: initially the time of the container holding the staking transaction; after completing a production quota, it becomes the time of the last completed container
- **Purchased points**: points can be bought through transactions; points counted toward ordering are capped
- **No slashing**: penalties only affect score and ordering; the staked principal is never deducted

### 2.4.4 Time Slots and Rotation

Production is organized in **20-second time slots**: **15 seconds of production + 5 seconds of synchronization**, with producers taking turns in deterministic order. The next producer starts only after confirming it is at the latest height, avoiding height forks; if the next producer suddenly fails, the following one in the ordering takes over.

A single nodeId leaves the producer cluster after producing **10,000 containers**, making room for new nodes; new nodes must likewise meet the stake and sync-height conditions.

### 2.4.5 Stake Lock and Exit

- At staking, the unlock time is set to +1 year; each valid container produced extends the unlock time to that container's time +1 year — preventing "honest early, malicious later, then run"
- The node owner can submit a **stop transaction** (irreversible): from then on there are no further extensions, score and ordering are reset to zero, and the node leaves the production state machine (it can still keep syncing); unstaking requires both stop and expiry
- To produce again, the owner must stake anew with a new address / nodeId

### 2.4.6 Transaction Routing and Caching

- Clients (apps / web) only need to submit transactions to **any node**; nodes outside the producer cluster relay transactions to the cluster, where they finally reach the current producer — this hides and protects producers and reduces the chance of attack
- Each producer maintains a transaction cache pool (keyed by txHash): it returns an acknowledgment on receipt and returns "system busy" when over capacity. All transactions go into the cache first and are taken out for production by the current producer; no API can enter the production flow directly
- Transaction distribution between caches is 100% asynchronous: P2P carries only light notifications, and data is always pulled over HTTP
- Neither entry nor relay performs ML-DSA-87 signature verification (expensive, and useless against malicious nodes); signatures are verified only when the producer produces. If verification fails, a light notification is sent over P2P and every node purges the corresponding txHash
- In an open protocol, any local check can be bypassed; only the hash of the distribution cache cannot. Nodes exchange cache hashes, and under-provisioned or dishonest nodes inevitably disagree with honest nodes and are excluded on that basis

### 2.4.7 Scale

- Producer cluster: at most **100** machines
- Each producer attaches sync / verification servers; the network-wide sync / verification cluster has at most **5,000** machines

### 2.4.8 Genesis Start

The first producer is the machine that receives the genesis activation command. Genesis activation first completes the asset allocation and then that producer's stake; only once there is a first producer does the network begin waiting for transactions to produce. Other nodes must first stake 10,000 QCC to join the cluster, and rotation begins only when the cluster has more than one producer.

---

## 2.5 Network and Synchronization

### 2.5.1 Two Network Layers

- **Producer P2P network**: producers form a network among themselves that carries only light communication (vouchers and notifications under 1 KB, reaching across continents within 500 ms) and never carries heavy data such as transactions — at high frequency, long-lived connections would be overwhelmed
- **Sync network**: a sync node only needs to connect to 1 producer; data security always relies on execution-layer hash consistency, and connecting to more producers adds no security

Data is always pulled over HTTP: the P2P network issues temporary access tokens to directly connected peers, and access is granted if either "cluster member IP" or "valid token" holds. QCC's external HTTP port is uniformly 9080.

The public chain core has no data security problem — all data is public — only a **performance security** problem: arbitrary computers must not be able to bring nodes down by pulling data. The network layer's protection therefore focuses on rate limiting and admission, not enterprise-style data encryption.

### 2.5.2 IPv6 First

QCC gives priority to the IPv6 standard. Most home broadband in Southeast Asia already supports IPv6, so home nodes are reachable inbound and can take part in the producer cluster; VPSs support both IPv4 and IPv6. At startup a node checks its network capabilities: a static public IPv4 address is used directly; otherwise a static IPv6 address is taken; if neither is available, the node is not allowed to join.

### 2.5.3 Synchronization Principles

- The container consensus voucher is the source of all truth; a node's state is always judged by "latest voucher height − local height", with no special cases (genesis, isolated and single-machine setups included)
- The sync network is a lightweight structure that works purely by pulling vouchers and containers over HTTP; it is also the prototype of future **lightweight developer nodes** (ordinary computers that do not produce and read data only for their own applications)
- The signature vault and public-key vault must be synced: they are not in containers, but without them replay verification is impossible

### 2.5.4 The Line Between Full Replay and Snapshots

- **Full replay**: any node can replay all containers from height 0 without relying on external or official snapshots. In compliance scenarios, a regulator can do a full replay, or a partial replay from a given height, as it wishes
- **Snapshots**: serve only new-node onboarding, auditing and evidence chains; they are generated only by **non-producers** (by default every 1,000 containers) and add no burden to the production path
- **Production-path cost approaches zero**: second-level user experience comes first; local rollback relies on replaying local containers, not snapshots
- Snapshots store only records with a balance greater than 0; addresses are managed by permanent long ids and accounts are never evicted, supporting hundreds of millions of addresses

---

## 2.6 State Machine Architecture

QCC does not take "a general-purpose virtual machine interpreting arbitrary code" as its core execution path; its core execution skeleton is a state machine architecture.

The basic idea: all on-chain writes are done through transactions, and the real consequences of transactions are executed by different state machines within explicit boundaries.

**Execution layer (statemachine)**: a single-threaded state machine running entirely in memory with no disk reads. It advances all state — balances, rules, stakes, sub-balances — and produces an execution-layer hash for each container.

**Index layer (stateindex)**: an independent process designed for 1–2 GB of memory, relying on local storage as much as possible. It serves index queries and is also the write service for produced containers; the producer state machine also lives in the index layer.

The execution layer and index layer run as two independent processes, so a super node can be split by load:

| Deployment scale | Form |
|---|---|
| Small | 1 machine runs all roles |
| Medium | Execution layer on the internal network, index layer public-facing — 2 machines |
| Very large | Split into five roles — pool / miner / hub / balance / index — deployed on the internal network; the pool role can be pooled across N machines (also providing DDoS protection) |

Inside the execution layer, state processing is divided by responsibility:

- **Balance state**: asset balances, debits, credits, freezes, unfreezes, distribution, ownership
- **Rule state**: rule publication, instantiation, permission constraints and effective boundaries
- **Stake state**: node stakes, authorized stakes, trust stakes and interest distribution
- **Sub-balance state machines**: carry "lock — condition — settle" flows such as open / win / cancel matching, lending and inheritance, each implemented independently by type without affecting the others

**The timestamp first principle**: all time judgments for transactions use only container time (the timestamp in the container header). All transactions in the same container share the same time value; neither a transaction's own time nor a server's local time is used — the precondition for consistent replay across the network.

**Deterministic execution order**: transactions in the same container are bucketed by type and executed in a fixed order (normal → open → loan → repay → cancelloan → win → cancel); producers cannot reorder across types.

The significance of the state machine architecture: verifiable, auditable, extensible, high-performance and highly secure — system boundaries are clear, the execution scope is controlled, and nothing is hidden in unexplainable arbitrary code.

---

## 2.7 The Rule Set

QCC's alternative to the traditional smart contract route is not simply opposition to code, but a different path:

> **Do not deploy arbitrary business code on chain; instantiate rule capabilities on chain.**

A rule is not a piece of code freely executed across the network, but a capability unit predefined by the system, callable by developers, and effective independently within asset boundaries.

QCC rules fall into five categories, all of which take part in the consensus computation of the execution-layer hash:

| Rule type | Purpose |
|---|---|
| Genesis rules (GodRule) | Define the initial system order; exist only in the genesis container |
| System rules (SystemRule) | Gas, system fund pools, network-wide operating boundaries; cannot be modified |
| Asset rules (AssetIdRule) | Asset issuance, minting, freezing, burning, whitelists, control transfer |
| User rules (UserRule) | Multisig, merchant, developer, tags, address end-of-life |
| Pledge rules (PledgeRule) | Node stakes, authorized stakes, trust stakes |

Core characteristics of the rule system:

- **Predefined rule capabilities**: the system first defines capability boundaries; developers choose and instantiate within them
- **Rules take effect only within asset boundaries**: asset A enabling freezing does not make asset B freezable
- **Rules serve business determinism**: the goal is not "Turing completeness" but explicit behavior, visible boundaries and verifiable consequences
- **No rule can transfer an owner's assets without the owner's signature** — the only exception is mechanisms the owner has authorized by signature in advance (such as inheritance and decentralized trading)

### 2.7.1 The Protocol Freeze Principle

QCC freezes its base consensus protocol at the first official release; once open-sourced and running it cannot be modified, and there is no fallback of "adding another layer later". Any new base protocol must therefore be completed before the freeze and must satisfy all three of the following:

1. **Universal use**: it serves all participants, not a specific business
2. **Must be implemented by the base protocol**: the application layer cannot substitute for it
3. **Satisfies full replay and execution-layer hash consistency**

Extension after the freeze follows the path of "extension protocol fully stored on chain as subchain genesis" (see Chapter 3).

---

## 2.8 A Unified Model for Assets and Data

Traditional blockchains usually treat "assets" and "data" as objects from two different worlds: assets transfer value, while data is only an attached description or external reference. QCC rebuilds this into one model.

In QCC, an asset is the unified identifier of an on-chain business object's ownership domain, rule domain and state domain. There are two main directions:

- **Financial assets**: the native coin, stablecoins, tokens, bill-type assets and equity-type assets, emphasizing issuance, transfer, freezing, minting, distribution, ownership and clearing
- **Data assets**: text, images, orders, financial reports, contracts, vouchers, logs and any byte data, emphasizing publication, reference, notarization, ownership and long-term retention; a single notarization holds at most **256 KB** of raw bytes

Both kinds of assets share a unified structure: both have an assetId, both enter the system through transactions, both can be bound to rules, both can enter containers, and both are processed by state machines. Asset IDs are unique across the chain; the chain rejects duplicate names.

Asset precision is chosen by the issuer between 0 and 9 decimals and may not exceed the 9-decimal precision of the QCC native coin; transaction amounts are expressed in the asset's own atomic units (for example, with precision 2, amount = 1000 means a face value of 10.00).

> Data itself can become an asset object that is defined, published, owned and processed by rules.

---

## 2.9 The Byte Protocol

QCC rebuilds not only on-chain objects but also how the chain communicates internally.

Traditional web systems talk to each other over HTTP and text protocols, but for an on-chain system that must carry high-frequency internal coordination, container transfer, state synchronization and consensus interaction, text protocols introduce too much redundancy and parsing cost. QCC therefore uses a Netty-based byte-level protocol on the critical paths inside and between nodes:

- **Byte-oriented rather than text-oriented**: internal communication uses byte frames, reducing transmission redundancy and parsing overhead
- **Frame-boundary oriented**: every internal request is a byte-level submission with explicit boundaries, operation and payload
- **Unified operation semantics**: internal module calls are built around unified operation tags and payload structures, making the internal network more like a system bus
- **Large-payload oriented**: for notarization payloads around 256 KB, the protocol layer uses explicit frame boundaries with segmentation and reassembly

Lightweight objects such as container consensus vouchers and node state vouchers are encoded purely as bytes with ByteBuffer. Nodes do not call each other like web pages; they cooperate as system modules at the byte level.

---

## 2.10 Post-Quantum Keys and the Account System

QCC's security system has targeted the post-quantum era from the very beginning.

### 2.10.1 Signature Algorithm: ML-DSA-87

| Parameter | Specification |
|---|---|
| Standard | ML-DSA-87 / NIST FIPS 204, security level 5 |
| Public key length | 2,592 bytes |
| Private key length | 4,864 bytes (standard private key) |
| Cross-platform | Java / Dart and all platforms unified on ML-DSA-87 |

ML-DSA-87 is the **only** signature algorithm in the QCC protocol, with no classical-algorithm fallback and no migration baggage.

### 2.10.2 Key Derivation: Mnemonic + Payment Password, Two Factors

QCC's key derivation is not a simple "mnemonic → private key", but a deterministic derivation in which the mnemonic and the payment password both take part:

```
seed = PBKDF2-SHA512(
    input      = mnemonic (UTF-8 bytes of 24 words),
    salt       = "ML-DSA-87:qcc-wallet:" + paymentPassword,
    iterations = 210,000,
    keyLength  = 32 bytes
)

ML-DSA-87 key pair = DeterministicMLDSA87.generateFromSeed(seed)
```

The payment password is injected as the PBKDF2 salt and takes part in seed generation at the cryptographic level, rather than encrypting the private key afterwards. The account recovery model is therefore:

> Mnemonic × payment password → deterministic seed → ML-DSA-87 key pair → address

Without either one, the same private key and the same address cannot be recovered.

### 2.10.3 A Leaked Mnemonic No Longer Means Lost Assets

Even if the mnemonic leaks accidentally, an attacker without the correct payment password cannot recover the corresponding private key, and the user still has a window to respond — moving assets urgently, rebuilding the account and abandoning the old address. This protection depends on the payment password being strong enough; if a mnemonic leak is suspected, the user should move assets and rebuild the account immediately.

### 2.10.4 Address Format

A standard QCC address (single-signature):

```
hash32   = SHA3-256(publicKey)
hash20   = hash32[0..19]                         // first 20 bytes
payload  = 0x3A + hash20                         // version byte 0x3A
checksum = SHA3-256(SHA3-256(payload))[0..3]     // double SHA3-256, first 4 bytes
address  = Base58(payload + checksum)
```

The version byte 0x3A makes the Base58 result **naturally start with Q and always be 34 characters long**, with no manual prefix needed; the address carries its own checksum and can be verified locally on the client. Multisig addresses use version byte 0x33, naturally start with M and are likewise always 34 characters.

### 2.10.5 Multisig: Joint Signing

QCC multisig is **joint signing**, not threshold multisig: there is no M-of-N ratio, and every transaction must be signed by **all** registered signers (like a criminal jury requiring a unanimous verdict rather than a majority vote). The number of signers is decided by the creator; once set, every transaction from that address requires 100% of the signatures.

A multisig address is derived deterministically from the sorted, de-duplicated public keys of all signers; the order of participants does not affect the address.

【TBD: write the derivation formula from `MultiSigAddrTool`; if not provided, keep the description of the principle above】

Multisig can be combined with asset rules and suits enterprises, institutions and high-value assets; stablecoin issuance requires multisig.

### 2.10.6 The Transaction Signing String

The object signed in a QCC transaction is a **canonical string of concatenated values**: it contains no field names, and fields are separated by backticks (`). The backtick is also a reserved system character and may not appear in any free-text field. This guarantees a strict one-to-one (injective) correspondence between the signing string and the transaction, and lets third-party developers in any language construct signatures with minimal effort.

Notarization transactions (EntityData) support up to 256 KB of data and sign the hash of the data rather than the full data.

### 2.10.7 Signature Vault and Public-Key Vault

Neither public keys nor signatures **go into containers**; each is stored in its own content-addressed database (the signature vault is addressed by SHA3-256(signature) and stored in 128 MB segments). Every node must sync both vaults, or it cannot replay and verify — so clients must not omit the public key from a transaction.

This layering is key to making post-quantum signatures practical: ML-DSA-87 signatures and public keys are kilobyte-sized, and putting them into containers would make the chain bloat quickly; stored in separate vaults, containers stay compact with no loss of verifiability.

### 2.10.8 Security Layers of the Account System

| Layer | Mechanism | What it protects |
|---|---|---|
| On-chain | ML-DSA-87 post-quantum signatures | Transaction validity and authentic ownership |
| Derivation | PBKDF2-SHA512 two-factor seed | Keys cannot be recovered from a single factor |
| Client | Local payment password protection | Convenience, and keys are not misused |

> If on-chain data and on-chain assets are to bear long-term trust, their signature system cannot just satisfy today — it must face the future.

---

## Chapter Summary

Chapter 2 answers the question: how does QCC, as a blockchain operating system, actually stand up technically?

- **Unified transactions**: every on-chain action converges into a standardized submission, through 5 API entry points
- **Container chain + tailHash**: data-driven containers, single-threaded chain-head advancement, SHA3-256 across the chain
- **Execution-layer hash consensus**: no voting, no signatures beyond transaction signatures; malicious containers are rolled back as empty slots
- **Producer cluster**: 10,000 QCC stake, 20-second slot rotation, heat-score ordering, no slashing — only score deductions — solving the production-refusal attack
- **Network and sync**: P2P carries only light notifications, data is pulled over HTTP, IPv6 first, a clear line between full replay and snapshots
- **State machines**: execution layer separated from index layer, the timestamp first principle, deterministic execution order
- **Rule set**: five rule categories; the protocol freezes at the first official release
- **Unified asset model**: value objects and data objects under one ledger logic
- **ML-DSA-87 + two-factor derivation + joint signing**, with separate signature and public-key vaults

QCC is not adding a few features to an old public chain; it is redefining how the base layer of a blockchain should be built if it is to serve complex real-world business, trusted data and long-term security.

---

# Chapter 3 What QCC Can Do

---

## 3.1 QCC's Two Main Directions

QCC's range of applications looks broad, but in essence it comes down to two main directions:

- **First, financial infrastructure**
- **Second, trusted data service infrastructure**

This division is possible because QCC itself has two kinds of base capabilities at once.

The first is **coordination of value, assets, rules and ledgers**. This means QCC handles not only transfers but also financial business such as stablecoins, asset tokens, decentralized trading, merchant payments, clearing and settlement, supply-chain bills and cross-ledger coordination.

The second is **on-chain byte data, trusted records, rule constraints, state machine execution and index retrieval**. This makes QCC not only a financial chain but also a trusted data foundation, able to serve AI, justice, bills, enterprise auditing, social content, mini-programs and many other scenarios that need "trusted records + verifiable rules + traceable state".

So "what QCC can do" should not be read as a scattering of features, but as:

> As a blockchain operating system, QCC can be the foundation of new financial structures and the foundation of trusted data services.

This is also an important difference between QCC and traditional public chains. Many chains can only extend along the single line of "asset transfer", while QCC, by unifying assets, rules, state machines and byte data, can naturally grow outward along both directions.

---

## 3.1.1 Financial Infrastructure

In finance, QCC does not serve only crypto trading in the narrow sense; it can serve two financial worlds at once:

- **Open finance and on-chain native finance**
- **The digital extension of the real-world financial system**

The former includes stablecoins, rule-based assets, open trading markets, decentralized matching, on-chain payments and native clearing; the latter includes merchant payments, regional ledger coordination, cross-border settlement, bill circulation, supply-chain finance and institutional ledger systems.

QCC can cover both because it does not see "finance" as a single transfer, but as a complete system of ledgers and rules:

- Assets can be defined
- Rules can be bound
- State can be executed
- Payments can be confirmed
- Records can be audited
- Multi-party collaboration can be written into the same trusted ledger

QCC's value in finance is therefore not "issuing a coin" but providing a deeper financial runtime.

---

## 3.1.2 Trusted Data Service Infrastructure

In trusted data, QCC's focus is not simply "putting data on chain", but giving data, once on chain, the following properties:

- Verifiable origin
- Long-term retention
- Rule constraints
- Indexed queries
- Audit and traceability
- A unified ledger relationship with assets and actions

This lets QCC serve not only notarization in the traditional sense but a much wider range of trusted data scenarios, such as:

- AI data provenance and model traces
- Judicial evidence and arbitration materials
- Enterprise financial reports, contracts, receipts and logs
- Bills, orders, delivery notes and product traceability records
- Social content, messages and mini-program publishing
- Industry-specific trusted business systems

In other words, QCC's trusted data service is not "writing down a file hash", but letting real-world business data enter the chain in a systematic way for the first time and take part in rule, state and audit logic.

QCC is therefore not merely a notarization chain, but trusted data service infrastructure.

---

## 3.2 Financial Infrastructure: What QCC Can Serve

Seen from finance, QCC does not serve a single financial product, nor only the speculative crypto market. It is more like an extensible financial base layer: it supports the most basic on-chain transfers and payments, as well as stablecoins, asset tokens, trading markets, cross-ledger coordination, merchant clearing and supply-chain finance.

The items in this section are not all financial scenarios, but the most representative capabilities.

---

## 3.2.1 Basic Transfers and On-Chain Payments

The most basic financial capability of any chain is transfer. But for QCC, a "transfer" is not just one address sending a digital balance to another; it is an on-chain payment action that can be confirmed, booked, receipted and brought into the rule system.

QCC's basic transfers and on-chain payments can therefore serve:

- Asset transfers between individuals
- Payment collection between merchants and users
- Cross-region micro-payments with instant arrival
- On-chain payments in a multi-asset environment
- The entry point for downstream clearing, callbacks and voucher generation

At the lowest level QCC can of course work like a payment chain; unlike traditional payment chains, however, a QCC payment is not an isolated action but can naturally combine with:

- Asset rules
- Merchant callbacks
- State machine updates
- Voucher records
- Data traces
- Later audits and indexed queries

That is, in QCC a payment is not only "money from A to B" but can also be:

- Confirmation that an order is complete
- The trigger condition of a merchant callback
- The starting point of an on-chain voucher
- The settlement result of cross-ledger collaboration

QCC's basic transfer capability is thus both the simplest entry point and the foundation of more complex financial scenarios.

---

## 3.2.2 Stablecoins and Asset Tokens

QCC can natively carry stablecoins as well as asset tokens in the broader sense. "Asset tokens" here are not hollow, purely conceptual token wrappers, but on-chain expressions of assets that correspond to real business objects, real ownership and real rule structures.

In QCC, an asset token can correspond not only to an abstract currency but also to:

- Financial reports
- Orders
- Dividend rights
- Bills
- Vouchers
- Equity records
- Internal institutional accounting objects
- Other asset units with explicit business meaning

QCC's asset tokenization is therefore not about creating more idle symbols, but about letting business objects that used to be scattered across databases, spreadsheets, paper documents and enterprise systems enter the chain for the first time, becoming:

- Definable assets
- Assets that can be bound to rules
- Auditable assets
- Assets that can be distributed, frozen, updated and pay dividends
- Assets that trading markets can connect to

Stablecoins are the most intuitive and mature of these. On QCC, a stablecoin can serve not only as a payment instrument but also in:

- Cross-border payments
- Merchant collection
- Regional clearing and settlement
- On-chain callbacks
- Open financial markets
- Institutional ledger coordination

So in QCC's financial world:

> Stablecoins solve "value anchoring"; asset tokens solve "how business objects are expressed on chain".

Together they form an important foundation of QCC's financial capabilities.

#### Compliant Stablecoins and Asset Rules

QCC's asset rules are designed for compliant stablecoins at the protocol level, and every constraint is irreversible, replayable and verifiable by anyone:

- **Issuance thresholds**: tokens can be issued freely — any asset ID not yet registered can be registered. Stablecoin issuance must be **multisig** and meet two thresholds: a fixed issuance Gas and a **100,000 QCC stake**. The stablecoin stake can be unlocked after 10 years, but this is not forced — the issuer decides whether to unlock, and the whole process is public on chain
- **Permissions declared at issuance**: freeze and burn capabilities must be chosen at issuance; if not chosen, the corresponding transactions can never be submitted — just as an app can only use the permissions it declared
- **Irreversible whitelist**: after issuance, the issuer submits a whitelist transaction to enable the whitelist. Once enabled, the asset can only ever circulate between whitelisted addresses and can never return to free circulation. Whitelist entries are added / removed incrementally, and the testnet has completed a **100-million-address** whitelist test; KYC / KYB information stays off chain and is mapped to addresses by the issuer
- **Freezing is orthogonal to the whitelist**: the whitelist governs eligibility, freezing governs fund flow; a frozen account can receive but not send, and a freeze can be lifted
- **Freeze, never confiscate**: no rule can transfer a user's assets to a third party. Assets at a frozen address can be burned by the issuer only after **12 consecutive months frozen** — a waiting period determined by consensus time that acts as a mandatory check on issuer power
- **Lost private keys can be recovered**: with the issuer's cooperation, "freeze the old address → burn after 12 months → mint → transfer to the new address" forms a public on-chain asset recovery path. QCC is thus the first public chain where "you lost your private key, but your assets can still be recovered"
- **Asset control transfer**: an asset owner can transfer the asset's controlling address to a new address through AssetChangeRule, taking effect in a single stage — suitable for mergers and acquisitions. Transfers of multisig-issued assets must be multisig; when transferring a single-signature asset, the owner can choose to upgrade to multisig control

---

## 3.2.3 Decentralized Trading and Rule-Based Asset Markets

When assets can be defined, rules can be bound and ledgers can be recorded uniformly, markets form naturally.

QCC can therefore carry not only stablecoins and asset tokens but also decentralized trading and rule-based asset markets. "Market" here does not mean only buy/sell matching in the narrowest sense, but an open on-chain circulation environment:

- Assets can be listed
- Assets can be matched
- Assets can be traded according to rules
- Trades enter on-chain confirmation and the index system
- Market behavior can be audited and traced

What makes QCC distinctive here is that it does not simply copy traditional order-book logic, but provides its own **Open / Win trading model**.

#### The Open / Win Trading Model

In QCC, the initiator first creates an `Open` transaction. The `Open` transaction produces an on-chain transaction hash, which becomes the base object for later market matching and settlement. A counterparty matches against that hash and its conditions and completes on-chain settlement.

This means a QCC market is not simply "posting an order"; the trade itself becomes an open on-chain request with explicit rule boundaries and a verifiable hash object.

#### Typical Forms of Open Transactions

QCC's `Open` transactions currently support the following typical market behaviors:

- Random distribution Open (e.g. random red-packet airdrops) — the random result comes from deterministic computation, identical for all nodes on replay
- Equal distribution Open (e.g. equal airdrops)
- Exchange-rate Open (spot trading object) — of the locked asset and the counter asset, at least one must be a stablecoin
- Dividend Open (asset dividends)
- Lending Open (loan / repay / cancelloan — borrowing, repayment and cancellation)
- Inheritance Open (see 3.2.4)

QCC's market capabilities thus apply not only to traditional buy/sell matching but also to "lock — condition — settle" flows such as distribution, dividends, lending and inheritance. All of these run in independent sub-balance state machines, use only container time and are fully replayable.

#### Exchange-Rate Objects and Spot Conditions

In the exchange-rate (spot) scenario, an `Open` transaction is not just a simple listing but carries explicit conditions. A counterparty can settle only if the conditions set by the initiator are met.

If a spot `Open` transaction cannot be filled completely in one match, the remainder does not expire immediately but can stay in the market for a set period. Under the current design, a remaining `Open` can **stay listed for 24 hours**, awaiting further matching.

#### Why Rule-Based Asset Markets Matter

The most distinctive point of QCC here is that what is traded is not only ordinary tokens but also **assets with rules**.

An object entering the market can carry, at the same time:

- Whether transfer is allowed
- Whether freezing is allowed
- Whether dividends are allowed
- Whether minting is allowed
- Whether there are merchant or institutional restrictions
- Whether specific conditions must be met to circulate

Such a market is no longer one where "any object flows freely like a meme coin", but something closer to a **rule-based asset market**.

From a market perspective, this means QCC is not only a chain suited to DEXs, but can also carry a system of rule-based asset issuance and circulation closer to an open private capital market.

In other words, QCC supports not only "a coin exchange" but, more broadly:

- On-chain asset markets
- Rule-based asset markets
- Voucher circulation markets
- Dividend-bearing equity markets
- On-chain circulation markets for bills and business objects

This is one of QCC's important possibilities in finance.

#### Implementation Evidence: Open / Win Is a Testable Market Primitive, Not a Concept

The source excerpt below shows that QCC's `Open / Win` transactions are not a conceptual design, but a market primitive that already supports single matching, concurrent taking and multi-round stress testing.

```java
// --- 1. Create an Open order (DEX mode) ---
long sellTotal = 100_000L * PRECISION;
TransactionData openTx = new TransactionData();
openTx.assetId = ASSET_SELL;
openTx.from = maker.address;
openTx.to = "DEX_POOL_" + System.currentTimeMillis();
openTx.amount = sellTotal;
openTx.txType = TranType.open.name();

MatchLogic logic = new MatchLogic();
logic.rule = MatchType.dex.name();
logic.pairAssetId = ASSET_BUY;
logic.rate = 1.5;
logic.maxParticipants = 100;
openTx.matchLogic = logic;

// --- 2. Create a Win order (buy) ---
TransactionData tx = new TransactionData();
tx.assetId = ASSET_BUY;
tx.from = taker.address;
tx.to = taker.address;
tx.txType = TranType.win.name();
tx.matcHash = openHash;
tx.amount = payAmount;
tx.timestamp = System.currentTimeMillis();
```

#### Automated Trading and Rule-Based Market Participation

QCC natively supports automated trading. But in QCC, automated trading is not a free off-chain script, nor a plug-in behavior outside the rule system; it is **part of the unified on-chain transaction model**.

This is because QCC follows the unified theory that "everything is a transaction": whether listing an `Open`, taking part in a `Win`, distributing, executing a conditional spot trade or more complex market behavior later, all of it is essentially an on-chain transaction that must enter the ledger and pay the corresponding Gas.

So automated bots in QCC do not exist at zero cost. Every participation is subject to:

- Gas paid by the transaction
- The transaction entering the on-chain confirmation path
- Temporary IP-based rate limiting at the transaction entry

QCC's view of automated trading is therefore not "whether bots are allowed", but:

> Make automated trading obey the same transaction rules, the same economic costs and the same network boundaries.

This has a very important result: automated trading in QCC is not an ecosystem loophole but can become ecosystem infrastructure. It brings liquidity, price discovery, distribution efficiency and rule-based asset circulation to the market, without naturally escaping the on-chain rule system.

Finer-grained conditions for automated participation — such as bot eligibility based on stake or authorization, or participation thresholds for specific assets or markets — are implemented by third-party applications on top of QCC's rule primitives, not added by the base protocol (the base protocol freezes at the first official release).

Automated trading on QCC is therefore not threshold-free, unaccountable, cost-free high-frequency predation, but an on-chain automated participation mechanism that is:

- Paid for
- Auditable
- Restrictable
- Constrained by rules
- Able to serve market liquidity sustainably

In the longer term this mechanism matters a great deal. As stablecoins, asset tokens, rule-based asset markets, merchant payments and regional coordination ledgers take shape, automated participants will include not only "bot traders" but also:

- Automated market makers
- Automated settlement agents
- Automated callback executors
- Automated payment routers
- AI-agent financial service programs

QCC also provides an `openhash` API to query all Open transactions currently available for participation. Automated programs therefore do not need to rely on private off-chain order books; they can query, filter and participate directly based on open on-chain request objects, forming a more standardized entry point for automated trading.

QCC supports automated trading not to encourage disorderly speculation, but to make on-chain markets, on-chain payments and on-chain financial collaboration run more efficiently.

---

## 3.2.4 Inheritance Transactions and Decentralized Trusts

Long-term ownership of assets is a question no financial infrastructure can avoid. Through inheritance transactions, QCC provides a decentralized family-trust primitive that does not depend on any institution:

- **Setup**: the asset owner signs an inheritance Open that locks an asset to a designated heir address, with an expiry condition measured in container time
- **Before expiry**: the owner can cancel, and the asset returns to the owner; the heir cannot claim it yet
- **After expiry**: the trust is irrevocable, and only the designated heir can claim the full principal; unknown addresses cannot claim, and repeated claims are invalid
- **Timestamp first principle**: expiry is judged only by container time and is unaffected by any server clock drift; the minimum lead time for setup is a consensus parameter (7 days on mainnet), identical for all nodes

Inheritance needs no new transaction type and fully reuses the unified open (setup) / win (claim) / cancel (revoke) model. The complete lifecycle — negative cases rejected without charge, principal locked, claim before expiry rejected, cancel before expiry refunded, claim by a stranger after expiry rejected, cancel after expiry rejected, full claim by the heir, repeated claims invalid — has passed end-to-end on the test chain, with sync nodes verifying the execution-layer hash at every height.

If the owner wants the address to be permanently unable to submit transactions afterwards, they can separately submit AddressEnd (address end-of-life) for that address; the heir's claim transaction is unaffected.

---

## 3.2.5 Regional and Global Coordination Ledger Networks

QCC's financial value does not have to show only in "the open public-chain market". More importantly, it can be used to build regional, industry-level and even cross-border coordination ledger networks.

In this model, QCC is not just a single ledger but a coordination base for multiple ledgers, institutions and regions. Different participants can implement their own ledger logic on QCC, for example:

- Public data enters the chain directly as bytes
- Private data enters the chain as encrypted bodies, hashes, mappings or indexes
- Each institution maintains its own state machine within its ledger scope
- Regional, institutional or industry ledgers interact and coordinate through QCC

This means banks, payment institutions, regional clearing organizations and industry financial platforms can, in principle, build their own on-chain ledger environments on QCC without relying entirely on a single centralized messaging network and database system.

From a practical financial perspective, QCC does not necessarily replace traditional cross-border financial networks directly, but in some scenarios it can provide more flexible on-chain coordination for:

- Regional payments
- Cross-ledger clearing and settlement
- Cross-border accounting coordination
- Merchant settlement networks
- Inter-institution data mapping and voucher synchronization
- Regional financial collaboration ledgers

QCC's key value here:

> It can keep not only its own chain's books, but also act as the coordination layer between multiple ledgers.

This makes it closer to real financial infrastructure than an ordinary "token-issuing chain".

---

## 3.2.6 Merchant Payments, Clearing and Callback Networks

QCC is well suited to carrying merchant payments, clearing and payment callback networks.

In merchant scenarios, what matters has never been only the single act of "payment succeeded", but the whole chain that follows:

- Order status updates
- Payment receipt generation
- Merchant callback triggers
- Accounting confirmation
- Clearing and settlement records
- Voucher traces
- Later dispute audits

QCC's unified transaction model, rule containers, state machines and index system can bring these steps — previously scattered across centralized backends — into one trusted ledger system.

In this structure, an on-chain payment can naturally produce:

- Payment status confirmation
- Merchant-side business logic callbacks
- Callback execution logs
- Clearing status transitions
- Later query and audit records

QCC can therefore do more than "transfers"; it can run a payment network much closer to real commerce.

QCC also provides a **merchant rule**: for payments and transfers of a merchant's asset, Gas is paid by the merchant, so end users can pay without holding QCC — exactly the experience a mass-market payment network needs.

For merchants, this matters because:

- Payments are not only confirmable but auditable
- Callbacks are not only executable but traceable
- Clearing has not only a result but a complete process record
- When a dispute arises, the ledger, vouchers and state chain can be traced back

In payments, QCC is therefore not only a settlement chain but on-chain payment and callback infrastructure for merchants, platforms and multi-party collaboration.

---

## 3.2.7 Supply-Chain Finance, On-Chain Bills and Product Traceability

QCC is equally well suited to supply-chain finance, on-chain bills and product traceability.

What these businesses have in common:

- Very high requirements for authentic records
- Very high requirements for process ordering
- Very high requirements for ownership and state changes
- Very high requirements for traceability and auditability
- Frequent multi-party collaboration

This matches QCC's containers, rules, state machines, indexing and trusted on-chain byte data naturally.

In supply-chain finance, QCC can carry:

- Order records
- Warehouse receipts
- Invoices
- Delivery receipts
- Bill circulation
- Receivables vouchers
- Upstream and downstream collaboration records

In product traceability, QCC can carry:

- Production batches
- Source records
- Circulation records
- Logistics node information
- Authenticity information
- After-sales traceability clues

In bills, QCC can further carry:

- Bill definition
- Bill ownership
- Bill transfer
- Bill state changes
- Mappings between bills and orders, vouchers and delivery records

QCC's value in this field is not only "letting data go on chain", but making sure that:

- Multi-party records in the supply chain enter a single trusted ledger
- Bills and vouchers are no longer just database fields but verifiable on-chain objects
- Product traceability no longer depends on a single company's backend, but is supported by a trusted chain of records

This gives QCC very practical capabilities in industrial finance and industrial collaboration.

---

## 3.2.8 Financial Extensibility as an On-Chain Operating System

The above are only representative cases of QCC in finance, not its limits.

As a blockchain operating system, QCC provides not a few fixed financial applications but a continually extensible set of financial base capabilities, including:

- Unified transactions
- Asset definition
- Rule binding
- State machine execution
- Container carrying
- Payment confirmation
- Clearing coordination
- Index retrieval
- Trusted records and long-term auditing

Developers, enterprises, institutions and regional networks can therefore keep building more financial scenarios on QCC, such as:

- Industry ledgers
- Regional clearing ledgers
- Internal institutional rule-based asset systems
- More complex dividend and equity circulation mechanisms
- Payment networks for specific regions or industries
- Private-sector financial tools based on trusted data

In other words, the financial scenarios in this chapter are not the upper limit of what QCC can do, only representative parts of what is already clearly established for QCC as financial infrastructure.

If traditional public chains are mostly about "moving financial assets on chain", QCC goes a step further — it tries to rebuild **the operating logic of finance itself** on chain.

---

## 3.3 Trusted Data Service Infrastructure: What QCC Can Serve

If financial infrastructure solves "value, assets and ledger collaboration", trusted data service infrastructure solves "how data, evidence, records and actions enter the chain in a trusted way".

QCC's value lies in not just writing "a data hash" on chain, but in bringing real-world byte data, business records, rule constraints and state changes into a trusted ledger system with a unified structure — giving data trusted publication, business actions trusted traces, evidence trusted retention and audit logs trusted traceability.

### 3.3.1 Entity Data On Chain and Trusted Notarization

One of QCC's most important differentiators is support for putting entity data on chain.

Entity data here does not mean just a hash digest, nor just an index pointer to an off-chain file, but text, images, file fragments and other real byte data themselves entering QCC's container structure and trusted ledger system.

QCC's notarization capability therefore does not only prove that "some data once existed", but goes further:

- The data itself, or its trusted structure, enters the chain
- The publication time of the data is verifiable
- The source of the data is verifiable
- State changes of the data are traceable
- The relationship between data and assets, rules and actions can be recorded uniformly

QCC is suited to carrying not only simple electronic notarization but also text publication, image and media fragment records, file-level business vouchers, business data such as contracts, orders, financial reports and logs, and more complex segmented data and byte-level objects.

On traditional chains, much so-called "notarization" only writes a hash into the chain, while the real data stays in off-chain systems, still exposed to loss, tampering, disconnection and difficulty of interpretation. QCC's direction is to let the data itself, its fragments or its trusted byte structure enter the on-chain organization as far as possible, so that "trusted notarization" is no longer a lightweight label but real on-chain data capability.

### 3.3.2 Enterprise-Grade Auditable Records and On-Chain Database Capability

What enterprises really need has never been just the words "data on chain", but: is the data trustworthy, queryable and auditable, are state changes completely traceable, and can it directly serve business systems?

QCC's value here comes from supporting not only data on chain, but also rule constraints, state machine processing, container carrying, native index retrieval and long-term ledger relationships. QCC can therefore do more than "record enterprise data"; it can support an enterprise-grade auditable record system.

An enterprise's financial reports, orders, receipts, settlement records, approval logs, business callback records, departmental collaboration records and important system event logs — once in QCC — are no longer just rows in a database, but part of a unified trusted ledger environment: with time, source and state changes, and in unified relationships with rules, payments, clearing, bills, contracts and vouchers.

More importantly, QCC's index state machine means this data does not merely "exist on chain" but can be retrieved, queried, aggregated, interpreted and used as a service.

> It is not only like a ledger; it begins to have the basic capabilities of an on-chain database.

Enterprises never lack places to "store data". What they lack is a trusted foundation, a unified record system, a ledger database that can be audited long term, and a trusted backend that connects with payments, bills, rules and business state.

### 3.3.3 Judicial Notarization, Arbitration and Trusted Evidence

Justice, arbitration and dispute resolution have very high requirements for data. The key question is not "can the data be seen", but: is the data trustworthy, has it been tampered with, when was it produced, who submitted it, is it complete, and is the chain of state changes traceable?

QCC fits this naturally because it can bring the key object types of judicial and evidence scenarios into one trusted ledger system: contracts, orders, receipts, chat records, transaction records, payment confirmations, callback logs, image and file bytes, arbitration materials, and business chains formed by multi-party collaboration.

In traditional dispute resolution, many problems come from broken evidence chains: files may be changed afterwards, screenshots may be forged, callback logs may be lost, time order is hard to prove uniformly, and different systems do not recognize each other's data. In QCC, these objects can enter the trusted ledger at the moment they are produced, forming a complete evidence system with provable publication time, verifiable submitter, checkable content, traceable state changes and mappable multi-party on-chain actions.

> Evidence is no longer just an off-chain screenshot or local file, but part of a trusted ledger environment that is verifiable, traceable and citable over the long term.

QCC is therefore well suited to judicial notarization, arbitration evidence, commercial dispute handling, multi-party evidence collection, contract performance tracking, and proof in payment receipt and settlement disputes. This is one of the most practical paths for trusted data services, and the one most likely to create social value.

### 3.3.4 AI Trusted Data, Model Traces and AI-Agent Collaboration

One of the biggest problems of the AI era is not only whether models are powerful, but: is the data source trustworthy, are model versions traceable, are outputs traceable, are AI agents' actions auditable, and does multi-agent collaboration have a unified ledger?

QCC has a natural advantage here, because AI systems depend heavily on three trusted capabilities: trusted data input, trusted action records and trusted result traces — which match QCC's capabilities closely.

Within QCC's trusted data framework, AI scenarios can include: training data source records, model version releases, inference result traces, prompt and context records, agent action chains, ledger-based tracking of multi-agent tasks, and trusted mappings between AI outputs and business objects.

For example, in an AI agent system: which agent started a task, which model it called, what context it used, what result it produced, and whether the result triggered a payment, callback, order, contract or other state change — all of this can enter QCC's unified ledger and index system.

QCC's core value in AI is not just notarization for AI, but the possibility of becoming the trusted data foundation for AI, the audit foundation for AI results, the collaboration ledger for AI agents and the trusted action record layer of the AI era — turning AI from "black-box output" into "verifiable action".

### 3.3.5 Social, Messaging, Mini-Programs and Content Publishing

QCC is not only a financial ledger, nor only an enterprise database. It also suits social, messaging, mini-program and content-publishing businesses — long-running, high-frequency, highly interactive and record-heavy.

A social system looks like "sending messages" on the surface, but in essence involves content generation, message flow, state changes, content ownership, time order, permission control, version traces and long-term citation. If all of this depends entirely on centralized backends, users usually cannot verify whether content was modified, whether the publication order is real, whether there was selective deletion, whether history was rewritten, or whether ownership of data and content is trustworthy long term.

QCC's on-chain byte data, rule containers, state machines and indexing make it well suited to: trusted content publication, trusted message traces, mini-program business records, citation and ownership of social content, community interaction records, and multi-party content collaboration with long-term tracking.

QCC supports flexible data expression: public content can go on chain directly, private content can go on chain encrypted, some indexes, hashes and mappings can go on chain, content state and receipts can go on chain, and message flows and business nodes can go on chain.

> A long-term trusted, traceable and verifiable base environment for content, messages, mini-programs and social interaction.

### 3.3.6 Application Publishing, the Developer Ecosystem and Industry-Level On-Chain Services

If QCC were only a protocol, it would struggle to form a long-term ecosystem. Its real value is that it provides not only the chain itself but a base platform on which developers publish applications, connect rules, organize assets, carry data and build industry services.

In QCC, developers do not "come to issue a token"; they can do something more complete: publish applications, define assets, bind rules, call payment capabilities, use containers to carry business objects, connect state machines and indexing, and build mini-program-style or industry-level on-chain services.

Because QCC unifies transactions, rules, assets, data, state machines, indexing and the byte protocol, developers building on QCC get not just "a transfer capability" but a whole set of system infrastructure.

This lets QCC serve a wider range of industry applications, such as: industry ledger systems, enterprise audit services, judicial evidence platforms, AI data platforms, supply-chain collaboration systems, merchant payment middle platforms, social and content distribution systems, and mini-program-style business networks.

> On one unified trusted foundation, build your own asset system, data system, rule system and application system.

This also means QCC's developer ecosystem is more adaptable across industries, rather than revolving only around pure financial protocols.

**Developer rewards are protocol-native, public and atomic.** Anyone can register as a developer by submitting a developer transaction from their own address in any wallet (admission is currently 100 QCC and automatically decreases over time with the Gas governance mechanism). From then on, any application transaction that carries that address in its `fromdev` field gives the developer a chain-level atomic reward, paid from the keyless developer reward pool. Anyone can take part, whether or not they can write code. Developer incentives on public chains worldwide are usually paid out by foundations as a black box; QCC's developer rewards are executed automatically by the protocol and can be checked by anyone.

### 3.3.7 Next-Generation Internet Security

Post-quantum security is not only a financial problem; global internet security must migrate and upgrade as a whole. QCC is not just a public chain but post-quantum infrastructure — with **tags + staking** as the root of decentralized authentication:

- **Tags**: anyone can apply to the chain for a tag (like a domain name, supporting any UTF-8 name) and obtain tag ownership state; tag ownership can be transferred
- **Authorized staking**: a user stakes QCC to a tag to join that ecosystem or obtain the corresponding authentication class; the interest from the stake belongs to the tag's beneficiary, so third-party developers only need users to stake in order to provide services
- **Account / server authentication**: implemented on tag ownership state and stake state
- **Encrypted access**: after authentication, encrypted access is established with keys negotiated via ML-KEM, so the transport layer is post-quantum as well

On this root, a set of decentralized internet services can be built:

- **namespace**: a decentralized user account system — account ownership returns from platforms to users
- **storagespace**: decentralized storage, built through asset authorization and crowdsourcing (e.g. QccS3: data is encrypted on the client, and storage nodes cannot see the content)
- **cdnspace**: a decentralized CDN server market based on storage
- **emailspace**: personal / enterprise email based on decentralized accounts, with optional notarization of email data

QCC will not develop these ecosystem applications on its own; it invites developers worldwide to build them together on these primitives. The QCC protocol itself does not depend on these services: super nodes are always full, symmetric replicas.

> Carrying on the spirit of Bitcoin, QCC belongs to all of humanity: no admin, no controller — only contributors. With next-generation internet security, individuals take back their rights and no longer depend on platforms for everything.

### 3.3.8 Independently Verifiable Applications for Society and Industry

Market research, elections, food safety, education, justice, trade — what these fields share is the need for a record system that **any authorized party can verify independently**.

QCC provides a foundation for such scenarios with assets + whitelists at the hundred-million scale + full byte-level notarization: eligibility is constrained by whitelists, process records all go on chain, and any authorized party can independently verify the integrity of specific data and the correctness of the process through full or partial replay, without having to trust any single institution.

### 3.3.9 Extension After the Freeze: Extension Protocol as Subchain Genesis

After QCC's base protocol is frozen, the world keeps evolving. QCC's answer:

> What a distributed system truly needs to agree on is not "all nodes run the same code", but "all nodes produce consistent, verifiable execution facts about how core state advances".

QCC therefore needs no unified virtual machine and no bytecode on chain:

- An extension protocol (rules, byte protocol, execution consistency algorithm) is published to QCC as a **full byte-level notarization** — the rule data is usually only tens of KB
- This on-chain protocol is equivalent to the **genesis block** of a new chain: nodes of the new system read the protocol from QCC to start, execute independently and compare execution-layer hashes at the same height
- After the protocol is published, **AddressEnd** is submitted for the publishing address, after which no new version can ever be published — the published protocol is permanently immutable
- The subchain produces its own data and need not return to QCC containers; it can be a public chain or a consortium chain, with no restriction on data form

There are only three development disciplines: state advances on a single thread; nondeterministic factors of any language must not enter the execution core; the goal is independent verifiability and mathematical credibility. An application only needs to hard-code the hash of the published protocol and check it against the notarization on QCC at startup — **the notarization on the public chain is the boundary the application cannot cross.**

### 3.3.10 Trusted Data Extensibility as an On-Chain Operating System

The above are only representative scenarios of QCC in trusted data, not its limits.

As a blockchain operating system, QCC provides not a few fixed notarization or data products, but a continually extensible set of trusted data base capabilities:

- Any byte data can enter a container as a data asset
- Data assets can be bound to rules, with lifecycles such as publication, versioning, freezing and citation
- State machines provide execution and indexing for data
- The byte protocol supports efficient transmission and persistence of large payloads
- The address system and signature mechanism make data ownership verifiable

If traditional chains are mostly about "proving that some data once existed", QCC goes further — it is not just a notarization tool, but a trusted data operating system in which the data itself, data actions, data rules and data state changes all enter the chain together. This is the final grounding of QCC's positioning as a "blockchain operating system".

---

## Chapter Summary

Chapter 3 answers: what can QCC, as a blockchain operating system, actually do in the real world?

The answer is two parallel paths:

- **Financial infrastructure**: starting from basic transfers and on-chain payments, extending to stablecoins and asset tokens, decentralized rule-based asset markets, inheritance and trusts, regional coordination ledger networks, merchant payments and clearing, supply-chain finance and bill circulation. QCC does not just "move assets on chain"; it rebuilds the operating logic of finance itself on chain.
- **Trusted data services**: starting from entity data on chain and trusted notarization, extending to enterprise audit records, judicial evidence systems, AI trusted action records, social and content publishing, the developer ecosystem and industry-level on-chain services. QCC does not just "leave a hash"; it gives data a complete trusted structure, rule boundaries and long-term traceability.

Both paths share the same base: containers carry objects, rules define boundaries, state machines drive execution, the index layer provides retrieval, the byte protocol supports transmission, and ML-DSA-87 guarantees security. On top of this, tags + staking form the authentication root of next-generation internet security, and extension protocols let QCC keep bootstrapping new systems even after its base layer is frozen.

QCC's end state is to become the foundation for trusted data, the foundation for trusted ledgers and the foundation for third-party on-chain applications — a blockchain operating system born for complex real-world business logic.

---

# Chapter 4 The QCC Native Coin and On-Chain Economic Rules

## 4.1 Introducing the QCC Native Coin

The QCC native coin is the base unit of value of the QCC public chain and the underlying fuel of the entire on-chain runtime.

It does not exist merely to issue a tradable symbol, but to support QCC's unified transaction model, rule execution model, data notarization model and ecosystem collaboration model. In QCC's system design, the native coin plays the following roles:

- The base payment unit for on-chain transactions
- The cost carrier for rule invocation and rule publication
- The fee carrier for data notarization and byte publication
- The basis for staking, production eligibility and on-chain eligibility boundaries
- A unified medium of value between developers, nodes, merchants and ecosystem participants

> The QCC native coin is the unified value foundation for all on-chain transactions, rules, data and ecosystem collaboration.

---

## 4.2 A Unified Cost Carrier: The Native Coin and the Transaction Model

One of QCC's base design principles is that "every on-chain action is expressed as a transaction". It follows that every on-chain action needs a unified cost carrier — and that carrier is the QCC native coin.

Every action is a transaction, every transaction has a cost, and every cost is borne by the QCC native coin — the two form a strict closed loop.

---

## 4.3 Supply, Precision and Unified Numeric Boundaries

The total supply of the QCC native coin is fixed at **210 million** (210,000,000), a tribute to Satoshi Nakamoto's 21 million. The native coin has **no freezing, no minting and cannot be burned**.

For precision, QCC uses **9 decimals**. All amounts are expressed as integers in the smallest unit, and ledger computation and state processing are based on the Java long type, keeping floating-point error out of the core state machine.

QCC constrains not only the native coin's precision but the whole chain's asset system:

> The precision of any token or asset on QCC is chosen by its issuer between 0 and 9 decimals and may not exceed the native coin's 9-decimal precision.

This establishes a unified numeric boundary for all assets: computation is consistent across the chain, and trades, settlement and state updates between different assets are handled uniformly.

Because the supply is fixed and cannot be increased, lost private keys are in themselves a natural form of deflation. QCC does not pursue unlimited precision or unlimited issuance; it uses a fixed supply, unified precision and a unified integer ledger to build a stable basis for value expression across the chain.

---

## 4.4 Gas and System Fund Pools

### 4.4.1 No Asset Ever Disappears

QCC's Gas mechanism follows a hard constraint: **every Gas deduction must return 100% to a system address; no asset may disappear into nothing.**

QCC has three system fund pool addresses:

| Address | Purpose |
|---|---|
| System address | System operation and producer support |
| Developer reward address | Atomic payment of fromdev developer rewards |
| Interest distribution address | Paying interest on native QCC stakes |

There is also the node stake pool, used only for the atomic movement of node stake funds in and out; it takes no part in Gas distribution.

These addresses have **no private keys at all**; funds move in and out automatically by system rules with atomic settlement. They use human-recognizable system constant forms, so anyone can confirm at a glance that they have no private key — for an open-source public chain and for regulators, auditability comes first.

When a reward recipient is unreachable (an invalid address format, or an address already marked dead by AddressEnd), the corresponding Gas always goes to the system address, never to the interest pool — no class of participant can profit from a system fault.

### 4.4.2 Gas Distribution

Gas from rule transactions, notarization transactions and ordinary transactions is distributed automatically by system rules among producers, the developer reward pool, the interest pool and the system address, forming an on-chain circular economy: the funding of the interest pool and the developer reward pool is thereby removed from anyone's control.

The real-time balances and distribution records of each fund pool are provided by a public API that anyone can query:

【TBD: Gas / fund pool query API path】

### 4.4.3 Fees Only Go Down

QCC's Gas factor (gFactor) is governed automatically by the protocol and **only goes down**:

- **First year after genesis**: statistics only, no adjustment — a full year of data sets the baseline TPS
- **Then evaluated every 30 days**: if the period's TPS is not below the baseline, the baseline ratchets up and gFactor stays the same; if below, gFactor is lowered in proportion to the gap, by at most 2% per period
- **Floor of 0.3**: protecting node income
- **A deterministic public commitment**: "when the evaluation happens" is deterministic, and anyone can calculate the next evaluation time in advance; "the result of the evaluation" depends on future real TPS. The protocol also provides a pure function for the worst-case floor, so anyone can independently calculate the value gFactor will not fall below in any future period

The developer admission fee decreases with the same factor. The fixed Gas for stablecoin issuance does not decay with gFactor.

QCC has no manual channel of any kind for adjusting Gas.

---

## 4.5 The Staking System

All QCC staking is implemented as rule transactions, with queryable and replayable state:

- **Node stake**: 10,000 QCC, a fixed protocol value that never changes; the only economic threshold for joining the producer cluster (see Chapter 2)
- **Trust stake**: supports only the QCC native coin; interest is paid to the staker from the interest distribution address every calendar month (converted from container time); the total balance of the interest pool is visible to the whole network
- **Authorized stake**: a user stakes to a tag, and the interest from the stake belongs to the tag's beneficiary rather than to the staker. Third-party developers only need users to stake QCC in order to provide services — the foundation of decentralized yield models and trust models; each stake is attached to exactly one tag
- **Stablecoin stake**: stablecoin issuance requires a 100,000 QCC stake, which can be unlocked after 10 years; whether to unlock is the issuer's decision

Interest accrues only on native QCC stakes; revenue distribution for other assets is done through separate dividend transactions and does not enter the interest pool.

---

## 4.6 The Native Coin's Many Roles

For **ordinary users**: the native coin is the basis for on-chain payment, on-chain operations and on-chain participation.

For **developers**: the native coin is the cost unit for application access, rule publication and data publication, and also the source of developer rewards.

For **merchants and institutions**: the native coin is the unified medium of value for payment, clearing and system operations; with the merchant rule enabled, merchants can pay Gas on behalf of users.

For **nodes**: the native coin is the threshold for production eligibility. Production rights do not belong to "whoever runs a node", but are determined by the 10,000 QCC stake together with replayable rules.

> The QCC native coin represents not only value, but also responsibility, eligibility and the cost of system order.

---

## Chapter Summary

- **Unified cost carrier**: every on-chain action is a transaction, and every transaction's cost is borne by the native coin
- **Chain-wide numeric basis**: a fixed supply of 210 million, 9 decimals, an integer ledger; no freezing, no minting, cannot be burned
- **Gas returns 100%**: three keyless system fund pools, no asset ever disappears, and distribution records are publicly queryable
- **Only goes down**: gFactor is governed automatically by the protocol, with no manual adjustment channel of any kind
- **Staking system**: node stakes, trust stakes, authorized stakes and stablecoin stakes, all replayable

---

# Chapter 5 The Genesis Container — QCC's Height-Zero Declaration

## 5.1 Definition and Unique Status of the Genesis Container

Testnet genesis container: https://test.qccio.com/v1/containerHeight/0 (the testnet and mainnet do not inherit from each other; mainnet will start from an entirely new genesis)

The genesis container is the only height-zero container in QCC, and the root starting point of the whole QCC system when it officially launches on the public network.

It is not a "first block" in the ordinary sense, nor an initialization file that can be filled in later, but a system-level primordial object that holds at the protocol layer, the node layer and the state machine layer at once. In QCC, all nodes, all state machines and the entire container chain that follows take the genesis container's hash and the official chain ID as their common starting point.

The anchor hash of the genesis container uses SHA3-256, consistent with the hash algorithm used across the chain.

Once the genesis container is published with official public-network parameters, its timestamp is fixed forever, its hash is fixed forever, its content is fixed forever, and its system status is fixed forever. All later data can only be written onward from container 1. The genesis container itself cannot be filled in later, tampered with or replaced, and cannot be regenerated after the container chain is running.

QCC elevates the genesis container to a system-level primordial object because it carries not only the genesis starting point but also the unified seal of rules, allocation, history and civilizational expression. QCC's rule root, allocation root, history root and civilization root all begin here.

QCC's intellectual property protection is built around this point too: as long as the genesis container is not modified, anyone can use QCC for free.

---

## 5.2 Technical Particularities

The genesis container has an independent technical status in QCC and does not entirely follow the usual carrying method of ordinary containers.

In the current implementation, the genesis container uses a specially designed receiving and parsing method, closer to a received file parsed according to a format predefined by the system. It can carry richer text, rules, allocations and multimedia structures, and uses a receiving method better suited to long-term fidelity, rather than simply reusing the generic transport of ordinary business containers.

The genesis container also starts the network: a dedicated genesis rule, in a genesis-format container, activates the first producer — first completing the asset allocation, then that producer's stake. Only with a first producer does the network begin producing containers; other nodes join the producer cluster after staking 10,000 QCC.

This parsing capability is not "learned" by nodes after publication, but written into the system before the public network starts: every node has the genesis container's source code and parsing logic built in, every state machine knows how to read its key structures, and the official chain ID, genesis hash and container format together form the network's startup consensus.

The genesis container's capacity is also specially designed. In the current implementation, it carries far more than an ordinary initialization object — currently on the order of several megabytes, expandable as the protocol requires — enough to carry genesis rules, initial allocations, messages, images, voice, short videos and encrypted content at the same time.

> The genesis container is special not because "it is an exception", but because it is the one primordial object the whole system agreed on before it started.

---

## 5.3 The One and Only Union of Three

In QCC's normal operation, transaction data, rule data and entity data are strictly isolated — container isolation, state machine isolation, rule boundary isolation. This is the core reason QCC can keep clear system order over long-term operation.

The genesis container is the only exception.

At height zero, QCC completes, through the genesis container, the one and only union of all three on the whole chain:

- **Transaction data**: value initialization structures such as genesis allocation, initial balances and lock-up logic
- **Rule data**: genesis-level rules, system-level parameters, rewards and permission boundaries
- **Entity data**: trusted byte content such as messages, images, voice, short videos and encrypted letters

This union does not break QCC's isolation philosophy; it is a higher-level proof:

> QCC could always handle value, rules and trusted data in one system; in normal operation it chooses to isolate them strictly for the sake of system order. The genesis container, through this one union, displays the whole system in full.

---

## 5.4 What the Genesis Container Holds

The genesis container holds not just a genesis hash or a list of initial balances, but the complete primordial structure QCC writes on chain at height zero:

- **Genesis-level system rules**: the official chain ID, genesis hash, system root parameters, genesis-level permissions and rule foundations — the common starting point for later nodes, state machines and container-chain consensus
- **Initial allocation and lock-up logic of the native coin**: the initial allocation of the QCC native coin, plus lock-up and release logic for some addresses — genesis allocation is not just balance initialization; it can create long-term constraints at the moment of genesis
- **Initial structure of the system fund pools**: including the genesis injection into the developer reward pool (50 million QCC, replenished afterwards by the Gas cycle), and other system-level resource structures defined by genesis rules
- **Text messages from genesis participants**: historical texts formally entering the height-zero primordial container, becoming part of the chain's permanent history
- **Multimedia such as images, voice and short videos**: raising the genesis record from a pure text ledger to a multimedia primordial object with a sense of its era and civilization
- **The founder's special historical content**: the founder keeps a higher level of space for historical expression — longer texts, explanations for the future, encrypted letters to the next generation and other legacy content

> Rules, allocation, value, text, images, sound and historical expression — a shared primordial structure, sealed at height zero once and for all.

---

## 5.5 Historical and Civilizational Significance

The value of the genesis container lies not only in its technical particularity, but in the fact that its history can never be repeated.

In ordinary blockchains, the genesis block is often just initial parameters and initial allocation. In QCC, the genesis container is also a permanent on-chain inscription — recording who took part at the moment of genesis, who left their words when the protocol was born, which images and sounds were left forever at the height-zero origin, and what spirit and legacy the founder wished to place in the first object of this chain.

It therefore has four layers of meaning: protocol significance (the system's root object), historical significance (the chain's one and only height-zero historical origin), cultural significance (raising a technical launch into a civilizational moment that can be remembered and witnessed), and artifact significance (if QCC ultimately has lasting influence, everything in the genesis container will become an irreplaceable historical digital artifact).

For this reason, the content of the genesis container has a strict boundary — it contains only what was written before mainnet height zero is officially published. This is decided by the protocol structure: once the genesis container is published, its timestamp is fixed, its hash is sealed forever, and all nodes take it as the only root. No later money, power or identity can ever enter the height-zero container itself.

> A place in the genesis container is not an economic seat but a historical one. It is not for sale; it belongs only to what was written before height zero.

---

## 5.6 The Founder's Legacy and Encrypted Messages

As the sole developer and founder, it is reasonable and necessary for the founder to keep a higher level of expressive space in the genesis container. This is not centralized abuse of power, but the historical place reserved for the founding role when the genesis container serves as the protocol's starting point.

This expression can include: longer text messages, a more complete historical account, images and multimedia, explanations and visions for the future, letters to the next generation, and encrypted private legacy content.

The design of encrypted messages deserves particular mention. The founder can write encrypted letters addressed to specific recipients in the genesis container, while publishing the ciphertext, key and related parameters. This gives them two layers of value at once: privacy (the founder's expression is preserved in a particular way) and verifiability (any developer can verify its authenticity with the public parameters).

This means the genesis container has not only rule and asset value but also real human expression and cross-generational legacy value — it is a protocol origin that truly carries "legacy", not just a ledger initialization file.

---

## Chapter Summary

The genesis container is QCC's one and only height-zero primordial container. Through a single, unrepeatable union of three — transactions, rules and entity data — it serves as the primordial sample in which QCC shows the world the full boundary of its capabilities.

Once published to the public network with the official chain ID and genesis hash, its content, timestamp, hash and system status are fixed forever. All later nodes, state machines and the evolution of the container chain can only unfold from it as the root — from container 1 onward is the history of the protocol's official operation.

The genesis container is not an end but a beginning. It seals the questions, ideals and courage of this generation, and waits for the next generation to keep writing the answers on the same chain.

> If QCC ultimately succeeds, the genesis container lives forever.

---

# Chapter 6 QCC's Long-Term Order and Ecosystem Path

## 6.1 QCC's Positioning as Public Chain and Operating System Infrastructure

QCC is positioned not just as "a public chain", nor just as "a blockchain project", but as a decentralized operating system for the future.

"Operating system" here is not a figure of speech: QCC itself carries operating-system-like base responsibilities — it uniformly carries transactions, rules, assets, entity data, state machines, the index system and on-chain applications, and provides a shared trusted foundation for different developers, institutions, nodes and business networks.

QCC's "decentralization" is likewise not only about the number of nodes, but about **structurally having no one in control**:

- QCC has **no admin anywhere**: no admin backend, no administrative address, no manual parameter channel, no emergency switch
- The base protocol is **frozen** at the first official release; after that no one — including the founder — can modify it
- Production rights are determined by the 10,000 QCC stake and replayable rules, not appointed by anyone
- The Gas factor is governed automatically by the protocol according to real TPS, and only goes down
- The system fund pools have no private keys at all and move funds atomically by rule

> QCC does not design a system of "who governs"; it is structurally built so that it does not need to be governed.

---

## 6.2 Rules Over Power

The long-term risk of traditional public chains often lies not in technology but in power: who can upgrade the protocol, who can change parameters, who can freeze assets, who decides a fork. QCC's answer: **structurally remove powers that can be abused, and write the constraints that must exist into rules.**

- **Protocol freeze**: after the first official release, the base protocol no longer changes. New capabilities can only appear as extension protocols fully stored on chain, serving as subchain genesis, without affecting QCC itself. A new base protocol must satisfy three conditions at once (see Chapter 2, 2.7.1)
- **Issuer power is constrained by rules**: an asset's freeze and burn capabilities must be declared at issuance and cannot be added afterwards; assets at a frozen address can only be burned after 12 consecutive months frozen, a period determined by container time that no one can shorten; once enabled, a whitelist cannot be revoked
- **Economic constraints replace governance votes**: producers are not chosen by vote but by stake and heat score; a misbehaving producer is not "slashed" — its container is rolled back and treated as an empty slot, and it naturally loses income and ordering
- **Time is decided by consensus**: all time semantics on chain — lock periods, inheritance lead time, interest periods, freeze periods — use container time, independent of anyone's local clock

Rules over power is not a slogan, but a set of constraints that are already implemented and can be independently verified.

---

## 6.3 Ecosystem Path: Asset Independence, Wolf-Pack Collaboration

QCC's ecosystem path does not rely on any single company to support it long term, nor on any centralized operator.

**Asset independence.** QCC is independent of any application party in terms of assets. OSN is QCC's first node operator and application party, but it is only the first node in the network; it does not own QCC and enjoys no protocol privilege. Anyone who stakes the same 10,000 QCC is under the same set of rules.

**Wolf-pack tactics.** QCC does not seek to have a single entity occupy every market, but lets many independent node operators, developers and institutions each take root in the regions and industries they know:

- Node operators deploy super nodes and take part in the producer cluster
- Developers build applications on the rule set and earn developer rewards through fromdev
- Institutions issue compliant stablecoins and assets with multisig and do business within rule boundaries
- Third parties provide trust, yield and custody services through authorized staking

**Open training.** After licensing, QCC provides free technical training to ecosystem participants, continually lowering the barriers to node deployment, rule configuration and application development.

---

## 6.4 Open-Source and Intellectual Property Path

QCC will ultimately be fully open source, planned in three steps to be completed before 2030:

1. **Open-source the developer website**: the QCC developer website opens first, as the ecosystem entry point and documentation center
2. **Open-source tools and interfaces**: wallets, SDKs, rule templates and peripheral tools open progressively
3. **Open-source the core protocol**: once the protocol is frozen and the network runs stably, the core implementation is fully open-sourced

On intellectual property, QCC applies for a patent only on **container sharding**, for defensive purposes: to prevent others from registering it first and then restricting the use of QCC, and to protect the uniqueness of the genesis container.

> As long as the genesis container is not modified, anyone can use QCC for free.

---

## 6.5 The QCC Native Coin and Long-Term Operating Order

QCC's long-term order ultimately comes back to the native coin and rules. The QCC native coin is not a symbol outside the system, but:

- **A unified transaction cost**: every on-chain action is a transaction, and its cost is ultimately borne by the native coin
- **A unified rule order**: rule publication and invocation both stand in an institutional relationship with the native coin
- **Unified incentives and constraints**: producer income, developer rewards, stake interest and production eligibility are all built around the native coin, and funded by the Gas cycle rather than by anyone's allocation

QCC aims to gradually reach a state in which:

- The protocol itself can run
- The rules themselves can constrain
- The incentives themselves can be distributed
- The nodes themselves can participate
- The developers themselves can be rewarded

And none of this requires anyone's permission, or is under anyone's control.

---

## 6.6 Long-Term Goal: From an Established Protocol to Global Trusted Infrastructure

QCC's longer-term vision is to become:

> **The underlying operating system of a global trusted byte network.**

This means QCC hopes to carry, at the same time:

- Global financial and payment collaboration
- Compliant stablecoin and rule-based asset networks
- Enterprise ledgers and trusted data services
- Supply-chain bills, auditing and judicial notarization
- AI data traces and AI-agent collaboration
- Next-generation internet account, storage and authentication security
- New-generation on-chain application systems built on it by developers

QCC's development path does not pursue short-term narratives or periodic hype. What it truly pursues is:

- **Long-term operability**
- **Long-term extensibility**
- **Long-term real-world adoption**
- **Long-term global accessibility**

> This chapter answers: how QCC goes from an established protocol to infrastructure that belongs to no one, yet can be accessed by everyone.

---

# Chapter 7 Test Network and Engineering Validation

## 7.1 This Is Not a Slide-Deck Project

The blockchain industry has no shortage of whitepapers; what it lacks is systems that actually run.

The QCC permanent testnet has been released and runs publicly. The data in this chapter comes from real measurements in real environments, and anyone can look up the genesis container, container height, transaction records, nodes and producer cluster status themselves:

- Testnet: https://test.qccio.com
- Node status: https://test.qccio.com/v1/qccnode
- Producer cluster status: https://test.qccio.com/v1/producer

The technical architecture described in this whitepaper — the container chain, execution-layer hash consensus, the producer cluster, state machines, the rule set, post-quantum accounts and the genesis container — is already running on the testnet. This is not a design drawing; it is a system that already exists.

---

## 7.2 Testnet Topology

The current public testnet consists of about 10 VPSs distributed across the public internet, with IPv6 networking preferred:

- **Producer cluster**: a 5-node cluster test has been completed — joining by stake, rotating production in 20-second slots, leaving when behind and rejoining after catching up, and exiting after 10,000 containers
- **Super node roles**: pool / miner / hub / balance / index roles online at the same time and working together
- **Execution layer and index layer in separate processes**: the execution layer is single-threaded and fully in memory; the index layer is an independent process
- **Node admission**: permissionless — a compliant address and an execution-layer hash matching the network are all that is needed to join

Compared with the earlier validation environment of 7 devices on a local network, the current testnet already runs on the real public internet.

---

## 7.3 Transaction Performance

On an ordinary AMD PC with 16 GB of memory (Windows 11), the QCC execution layer measures about **1,000 TPS**.

For reference:

| Chain | Public TPS reference |
|---|---|
| Bitcoin | about 7 TPS |
| Ethereum | about 15–30 TPS |
| QCC (single ordinary PC, execution layer) | about 1,000 TPS |

Note that this figure comes from ordinary home hardware with no special optimization. QCC's execution layer is a single-threaded, fully in-memory deterministic state machine whose performance depends mainly on single-core speed and memory; higher performance is expected on professional hardware.

---

## 7.4 Trusted Data Notarization Performance

QCC supports putting entity data natively on chain — not just writing a hash, but bringing real byte data into containers and the ledger system. The earlier testnet completed a notarization performance test of 10,000 entity data records:

| Metric | Value |
|---|---|
| Total test records | 10,000 |
| Average TPS | 8 TPS |
| Peak TPS | 24 TPS |
| Test environment | 7 devices on a WiFi local network |

Putting entity data on chain differs fundamentally in system load from putting ordinary transactions on chain — each record carries real byte content, placing far higher demands on storage, transmission, parsing and state machine processing than an ordinary transfer. Very few public chains natively support entity data on chain, and among mainstream blockchains there is almost no directly comparable performance reference.

---

## 7.5 Key Feature Validation

| Item | Result |
|---|---|
| Stablecoin whitelist | Passed at 100 million addresses |
| On-chain inheritance | End-to-end tests passed 8/8 |
| Address manager | 2.1-billion-address test build running; 100-billion capacity design complete, delivered in the validation phase |
| Producer cluster | 5-node cluster test passed |
| Snapshots and replay | Snapshots generated by non-producers; full replay from height 0 matches the network state |
| Post-quantum accounts | ML-DSA-87 signatures and two-factor key derivation running on the testnet |

---

## 7.6 From Testnet to Mainnet: What Remains

Being honest about the distance between current progress and mainnet is the most direct way to build trust.

**What the testnet has validated:**

- Container chain structure, execution-layer hash consensus and chained executeHash
- Producer cluster joining, rotation, leaving and rejoining
- The system topology with execution layer and index layer in separate processes
- The rule set, compliant stablecoins, on-chain inheritance and developer rewards
- Entity data on chain and trusted notarization
- The genesis container structure (queryable on the testnet)
- Post-quantum accounts and the signature system

**Work remaining before mainnet:**

- Delivery of the 100-billion-capacity address manager
- Larger producer clusters and public-network stress tests
- Confirmation and publication of the official mainnet genesis container parameters (mainnet does not inherit testnet data)
- Full productization of the explorer, wallet and rule templates
- Step one of the open-source path: open-sourcing the developer website

The QCC permanent testnet will run long term as the public environment for developer access, rule validation and application testing.

---

# Conclusion

QCC begins with finance and ends with history.

Through a secure, post-quantum foundation, I hope to build a trusted notebook for humanity that lasts a hundred years — so that from now on, history can be written by everyone, kept by everyone and proven by everyone.

It belongs to no one, and needs no one's permission.

---

QCC Whitepaper (English v2.0)

Quantum Container Chain – Blockchain Operating System

Published: October 2026

Author: FChat / Founder of QCC

Email: fchatth@gmail.com

fChat app id: 4444444
