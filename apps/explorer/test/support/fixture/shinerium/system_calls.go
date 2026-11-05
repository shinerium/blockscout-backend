// Writes system_calls.json, the test vectors of
// Explorer.Chain.Shinerium.SystemCall: the node's system-contract requests
// encoded with go-ethereum's rlp, the encoder the node's rlplib derives from.
// The structs copy the node's field order, types and tags at 0.2.0-80a4fd89
// (core/validatorbond/bond.go, core/council/proposal.go,
// core/accountkeys/accountkeys.go, core/binaryregistry/registry.go).
//
//	go mod init vectors && go get github.com/ethereum/go-ethereum/rlp@v1.14.12
//	go run system_calls.go > system_calls.json
package main

import (
	"bytes"
	"encoding/hex"
	"encoding/json"
	"math/big"
	"os"

	"github.com/ethereum/go-ethereum/common"
	"github.com/ethereum/go-ethereum/rlp"
)

type BondRequest struct {
	Op         uint64
	EdPublic   []byte
	BlsPublic  []byte
	Withdrawal common.Address
	Nonce      uint64
	Proof      []byte
	BlsProof   []byte
	Commitment []byte         `rlp:"optional"`
	Name       []byte         `rlp:"optional"`
	PQPublic   []byte         `rlp:"optional"`
	NewOwner   common.Address `rlp:"optional"`
}

type CouncilRequest struct {
	Op        uint64
	Identity  []byte
	PQPublic  []byte
	Nonce     uint64
	Proposal  uint64
	Kind      uint64
	Account   uint64
	Target    []byte
	Amount    []byte
	Data      common.Hash
	Choice    uint64
	Rationale common.Hash
	Proof     []byte
}

type AccountKeysRequest struct {
	Op        uint64
	Scheme    uint8 // pqsig.ID
	PublicKey []byte
	Policy    uint8 // accountkeys.Policy
	Proof     []byte
}

type RegistryRequest struct {
	Op        uint64
	Binary    common.Hash
	Version   uint64
	From      uint64
	Signer    []byte
	Sequence  uint64
	Signature []byte
}

func rep(b byte, n int) []byte { return bytes.Repeat([]byte{b}, n) }

type vector struct {
	Contract string `json:"contract"`
	Case     string `json:"case"`
	Input    string `json:"input"`
}

func main() {
	identity := rep(0x11, 32)
	pq := rep(0x55, 1312)
	pqSmall := rep(0x55, 300)
	withdrawal := common.HexToAddress("0x2b2a63c920f8b7a3f1c1b2e5d6a0e8c3f4a5b6c7")
	newOwner := common.HexToAddress("0xb67a9585000000000000000000000000000000aa")
	rationale := common.BytesToHash(rep(0x66, 32))
	amount := new(big.Int).Mul(big.NewInt(1000), new(big.Int).Exp(big.NewInt(10), big.NewInt(18), nil)).Bytes()

	cases := []struct {
		contract, name string
		req            interface{}
	}{
		{"ValidatorBond", "deposit", BondRequest{Op: 1, EdPublic: identity, BlsPublic: rep(0x22, 48), Withdrawal: withdrawal, Nonce: 3, Proof: rep(0x33, 64), BlsProof: rep(0x44, 96), PQPublic: pq}},
		{"ValidatorBond", "requestExit", BondRequest{Op: 2, EdPublic: identity}},
		{"ValidatorBond", "beginRelease", BondRequest{Op: 3, EdPublic: identity}},
		{"ValidatorBond", "withdraw", BondRequest{Op: 4, EdPublic: identity}},
		{"ValidatorBond", "reportConflict", BondRequest{Op: 5, EdPublic: identity, Proof: rep(0x77, 300)}},
		{"ValidatorBond", "signingReset", BondRequest{Op: 6, EdPublic: identity, Proof: rep(0x33, 64), Commitment: rep(0x88, 32), PQPublic: pqSmall}},
		{"ValidatorBond", "setName", BondRequest{Op: 7, EdPublic: identity, Proof: rep(0x33, 64), Name: []byte("validator-one"), PQPublic: pqSmall}},
		{"ValidatorBond", "transferOwner", BondRequest{Op: 8, EdPublic: identity, NewOwner: newOwner}},
		{"ValidatorBond", "topUp", BondRequest{Op: 9, EdPublic: identity}},
		{"ValidatorBond", "unknown", BondRequest{Op: 12, EdPublic: identity}},
		{"Council", "proposeTransfer", CouncilRequest{Op: 1, Identity: identity, PQPublic: pqSmall, Nonce: 1, Kind: 1, Account: 1, Target: withdrawal.Bytes(), Amount: amount, Data: common.BytesToHash(rep(0x99, 32)), Rationale: rationale, Proof: rep(0x33, 300)}},
		{"Council", "proposeCollateral", CouncilRequest{Op: 1, Identity: identity, PQPublic: pqSmall, Nonce: 2, Kind: 4, Amount: amount, Data: common.BytesToHash(rep(0x99, 32)), Rationale: rationale, Proof: rep(0x33, 300)}},
		{"Council", "voteNo", CouncilRequest{Op: 2, Identity: identity, PQPublic: pqSmall, Nonce: 3, Proposal: 7, Choice: 2, Rationale: rationale, Proof: rep(0x33, 300)}},
		{"Council", "voteYesSmall", CouncilRequest{Op: 2, Identity: identity, Nonce: 1, Proposal: 7, Choice: 1, Rationale: rationale}},
		{"Council", "execute", CouncilRequest{Op: 3, Proposal: 7}},
		{"Council", "object", CouncilRequest{Op: 4, Identity: identity, PQPublic: pqSmall, Nonce: 4, Proposal: 300, Rationale: rationale, Proof: rep(0x33, 300)}},
		{"AccountKeys", "register", AccountKeysRequest{Op: 1, Scheme: 0x10, PublicKey: pq, Policy: 1, Proof: rep(0x33, 2420)}},
		{"AccountKeys", "registerSmall", AccountKeysRequest{Op: 1, Scheme: 0x20, PublicKey: rep(0x56, 8), Policy: 2, Proof: rep(0x33, 8)}},
		{"AccountKeys", "rotate", AccountKeysRequest{Op: 2, Scheme: 0x20, PublicKey: rep(0x56, 897), Policy: 2, Proof: rep(0x33, 300)}},
		{"AccountKeys", "setPolicy", AccountKeysRequest{Op: 3, Policy: 2, Proof: rep(0x33, 300)}},
		{"AccountKeys", "clear", AccountKeysRequest{Op: 4}},
		{"BinaryRegistry", "approve", RegistryRequest{Op: 1, Binary: common.BytesToHash(rep(0xaa, 32)), Version: 2000, Signer: rep(0x12, 32), Signature: rep(0x34, 64)}},
		{"BinaryRegistry", "require", RegistryRequest{Op: 2, Version: 2001, From: 1793900000, Signer: rep(0x12, 32), Signature: rep(0x34, 64)}},
		{"BinaryRegistry", "attest", RegistryRequest{Op: 3, Binary: common.BytesToHash(rep(0xaa, 32)), Signer: identity, Sequence: 5, Signature: rep(0x34, 64)}},
	}

	out := make([]vector, 0, len(cases))
	for _, c := range cases {
		b, err := rlp.EncodeToBytes(c.req)
		if err != nil {
			panic(err)
		}
		out = append(out, vector{c.contract, c.name, "0x" + hex.EncodeToString(b)})
	}
	enc := json.NewEncoder(os.Stdout)
	enc.SetIndent("", "  ")
	if err := enc.Encode(out); err != nil {
		panic(err)
	}
}
