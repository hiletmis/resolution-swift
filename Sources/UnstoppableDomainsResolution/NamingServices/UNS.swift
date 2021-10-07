//
//  uns.swift
//  resolution
//
//  Created by Johnny Good on 8/11/20.
//  Copyright © 2020 Unstoppable Domains. All rights reserved.
//

import Foundation

internal class UNS: CommonNamingService, NamingService {
    var layer1: UNSLayer!
    var layer2: UNSLayer!
    let asyncResolver: AsyncResolver

    static let name: NamingServiceName = .uns

    init(_ config: UnsLocations) throws {
        self.asyncResolver = AsyncResolver()
        super.init(name: Self.name, providerUrl: config.layer1.providerUrl, networking: config.layer1.networking)
        let layer1Contracts = try parseContractAddresses(config: config.layer1)
        let layer2Contracts = try parseContractAddresses(config: config.layer2)

        self.layer1 = try UNSLayer(name: .layer1, config: config.layer1, contracts: layer1Contracts)
        self.layer2 = try UNSLayer(name: .layer2, config: config.layer2, contracts: layer2Contracts)

        guard self.layer1 != nil, self.layer2 != nil else {
            throw ResolutionError.proxyReaderNonInitialized
        }
    }

    private func parseContractAddresses(config: NamingServiceConfig) throws -> [UNSContract] {
        var contracts: [UNSContract] = []
        var proxyReaderContract: UNSContract?
        var unsContract: UNSContract?
        var cnsContract: UNSContract?

        let network = config.network.isEmpty
            ? try Self.getNetworkId(providerUrl: config.providerUrl, networking: config.networking)
            : config.network

        if let contractsContainer = try Self.parseContractAddresses(network: network) {
            unsContract = try getUNSContract(contracts: contractsContainer, type: .unsRegistry, providerUrl: config.providerUrl)
            cnsContract = try getUNSContract(contracts: contractsContainer, type: .cnsRegistry, providerUrl: config.providerUrl)
            proxyReaderContract = try getUNSContract(contracts: contractsContainer, type: .proxyReader, providerUrl: config.providerUrl)
        }

        if config.proxyReader != nil {
            let contract = try super.buildContract(address: config.proxyReader!, type: .proxyReader, providerUrl: config.providerUrl)
            proxyReaderContract = UNSContract(name: "ProxyReader", contract: contract, deploymentBlock: "earliest")
        }

        guard proxyReaderContract != nil else {
            throw ResolutionError.proxyReaderNonInitialized
        }
        contracts.append(proxyReaderContract!)
        if config.registryAddresses != nil && !config.registryAddresses!.isEmpty {
            try config.registryAddresses!.forEach {
                let contract = try super.buildContract(address: $0, type: .unsRegistry, providerUrl: config.providerUrl)
                contracts.append(UNSContract(name: "Registry", contract: contract, deploymentBlock: "earliest"))
            }
        }

        // if no registryAddresses has been provided to the config use the default ones
        if contracts.count == 1 {
            guard unsContract != nil else {
                throw ResolutionError.contractNotInitialized("UNSContract")
            }
            guard cnsContract != nil else {
                throw ResolutionError.contractNotInitialized("CNSContract")
            }
            contracts.append(unsContract!)
            contracts.append(cnsContract!)
        }

        return contracts
    }

    private func getUNSContract(contracts: [String: CommonNamingService.ContractAddressEntry], type: ContractType, providerUrl: String ) throws -> UNSContract? {
        if let address = contracts[type.name]?.address {
            let contract = try super.buildContract(address: address, type: type, providerUrl: providerUrl)
            let deploymentBlock = contracts[type.name]?.deploymentBlock ?? "earliest"
            return UNSContract(name: type.name, contract: contract, deploymentBlock: deploymentBlock)
        }
        return nil
    }

    func isSupported(domain: String) -> Bool {
        return layer2.isSupported(domain: domain)
    }

    func owner(domain: String) throws -> String {
        return try asyncResolver.safeResolve(
            l1func: self.layer1.owner(domain: domain),
            l2func: self.layer2.owner(domain: domain)
        )
    }

    func record(domain: String, key: String) throws -> String {
        return try asyncResolver.safeResolve(
            l1func: self.layer1.record(domain: domain, key: key),
            l2func: self.layer2.record(domain: domain, key: key)
        )
    }

    func records(keys: [String], for domain: String) throws -> [String: String] {
        return try asyncResolver.safeResolve(
            l1func: self.layer1.records(keys: keys, for: domain),
            l2func: self.layer2.records(keys: keys, for: domain)
        )
    }

    func getTokenUri(tokenId: String) throws -> String {
        return try asyncResolver.safeResolve(
            l1func: self.layer1.getTokenUri(tokenId: tokenId),
            l2func: self.layer2.getTokenUri(tokenId: tokenId)
        )
    }

    func getDomainName(tokenId: String) throws -> String {
        return try asyncResolver.safeResolve(
            l1func: self.layer1.getDomainName(tokenId: tokenId),
            l2func: self.layer2.getDomainName(tokenId: tokenId)
        )
    }

    func addr(domain: String, ticker: String) throws -> String {
        return try asyncResolver.safeResolve(
            l1func: self.layer1.addr(domain: domain, ticker: ticker),
            l2func: self.layer2.addr(domain: domain, ticker: ticker)
        )
    }

    func resolver(domain: String) throws -> String {
        return try asyncResolver.safeResolve(
            l1func: self.layer1.resolver(domain: domain),
            l2func: self.layer2.resolver(domain: domain)
        )
    }

    func tokensOwnedBy(address: String) throws -> [String] {
        let results = try asyncResolver.resolve(
            l1func: self.layer1.tokensOwnedBy(address: address),
            l2func: self.layer2.tokensOwnedBy(address: address)
        )
        var tokens: [String] = []

        let l2Results = results[.layer2]!
        let l1Results = results[.layer1]!

        guard l2Results.1 == nil else {
            throw l2Results.1!
        }

        guard l1Results.1 == nil else {
            throw l1Results.1!
        }

        tokens += l2Results.0!
        tokens += l1Results.0!

        return tokens.uniqued()
    }

    func batchOwners(domains: [String]) throws -> [String?] {
        let results = try asyncResolver.resolve(
            l1func: self.layer1.batchOwners(domains: domains),
            l2func: self.layer2.batchOwners(domains: domains)
        )
        var owners: [String?] = []
        let l2Result = results[.layer2]!
        let l1Result = results[.layer1]!

        guard l2Result.1 == nil else {
            throw l2Result.1!
        }

        guard l1Result.1 == nil else {
            throw l1Result.1!
        }

        for (l2owner, l1owner) in zip(l2Result.0!, l1Result.0!) {
            let ownerAddress = l2owner == nil ? l1owner : l2owner
            owners.append(ownerAddress)
        }
        return owners
    }
}

fileprivate extension Sequence where Element: Hashable {
    func uniqued() -> [Element] {
        var set = Set<Element>()
        return filter { set.insert($0).inserted }
    }
}
