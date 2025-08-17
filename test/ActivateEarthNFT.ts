import { expect } from "chai";
import { ethers } from "hardhat";
import { ActivateEarthNFT } from "../typechain-types";
import { SignerWithAddress } from "@nomicfoundation/hardhat-ethers/signers";
import { MerkleTree } from "merkletreejs";

describe("ActivateEarthNFT", function () {
  let nftContract: ActivateEarthNFT;
  let owner: SignerWithAddress;
  let guard1: SignerWithAddress;
  let guard2: SignerWithAddress;
  let user1: SignerWithAddress;
  let user2: SignerWithAddress;
  let users: SignerWithAddress[];

  const TEST_NFT_TYPE = {
    name: "Bronze Tier",
    baseURI: "https://api.activateearth.com/metadata/bronze/",
    price: ethers.parseEther("0.01"),
    maxSupply: 100,
    maxPoolNumber: 5,
    freeMintNumber: 10,
  };

  const TEST_NFT_TYPE_2 = {
    name: "Silver Tier",
    baseURI: "https://api.activateearth.com/metadata/silver/",
    price: ethers.parseEther("0.05"),
    maxSupply: 50,
    maxPoolNumber: 10,
    freeMintNumber: 5,
  };

  beforeEach(async function () {
    [owner, guard1, guard2, user1, user2, ...users] = await ethers.getSigners();

    const NFTFactory = await ethers.getContractFactory("ActivateEarthNFT");
    nftContract = await NFTFactory.deploy(guard1.address, guard2.address);
    await nftContract.waitForDeployment();

    // Add test NFT type
    await nftContract.addNftType(TEST_NFT_TYPE);
  });

  describe("Deployment", function () {
    it("Should set the correct owner", async function () {
      expect(await nftContract.owner()).to.equal(owner.address);
    });

    it("Should set the correct guards", async function () {
      const guards = await nftContract.getGuards();
      expect(guards[0]).to.equal(guard1.address);
      expect(guards[1]).to.equal(guard2.address);
    });

    it("Should initialize with zero NFT types", async function () {
      const NFTFactory = await ethers.getContractFactory("ActivateEarthNFT");
      const emptyNFT = await NFTFactory.deploy(guard1.address, guard2.address);
      expect(await emptyNFT.getNftTypeCounter()).to.equal(0);
    });

    it("Should revert with same guard addresses", async function () {
      const NFTFactory = await ethers.getContractFactory("ActivateEarthNFT");
      await expect(
        NFTFactory.deploy(guard1.address, guard1.address)
      ).to.be.revertedWithCustomError(nftContract, "InvalidGuardAddress");
    });
  });

  describe("NFT Type Management", function () {
    it("Should add NFT type correctly", async function () {
      await nftContract.addNftType(TEST_NFT_TYPE_2);

      const nftType = await nftContract.getNftType(1);
      expect(nftType.name).to.equal(TEST_NFT_TYPE_2.name);
      expect(nftType.price).to.equal(TEST_NFT_TYPE_2.price);
      expect(nftType.maxSupply).to.equal(TEST_NFT_TYPE_2.maxSupply);
      expect(nftType.isActive).to.be.true;
    });

    it("Should update NFT type correctly", async function () {
      const updatedType = {
        ...TEST_NFT_TYPE,
        name: "Updated Bronze",
        price: ethers.parseEther("0.02"),
      };

      await nftContract.updateNftType(0, updatedType, true);

      const nftType = await nftContract.getNftType(0);
      expect(nftType.name).to.equal("Updated Bronze");
      expect(nftType.price).to.equal(ethers.parseEther("0.02"));
    });

    it("Should update NFT type status", async function () {
      await nftContract.updateNftTypeStatus(0, false);

      const nftType = await nftContract.getNftType(0);
      expect(nftType.isActive).to.be.false;
    });

    it("Should revert when non-owner tries to add NFT type", async function () {
      await expect(
        nftContract.connect(user1).addNftType(TEST_NFT_TYPE_2)
      ).to.be.revertedWithCustomError(
        nftContract,
        "OwnableUnauthorizedAccount"
      );
    });

    it("Should revert with invalid NFT type inputs", async function () {
      const invalidType = {
        ...TEST_NFT_TYPE,
        name: "", // Invalid empty name
      };

      await expect(
        nftContract.addNftType(invalidType)
      ).to.be.revertedWithCustomError(nftContract, "NameLengthInvalid");
    });
  });

  describe("Minting", function () {
    it("Should mint NFT with correct payment", async function () {
      const mintPrice = TEST_NFT_TYPE.price;

      await expect(nftContract.connect(user1).mint(0, { value: mintPrice }))
        .to.emit(nftContract, "NFTMinted")
        .withArgs(user1.address, 1, 0);

      expect(await nftContract.getUserOwnedNFT(user1.address, 0)).to.be.true;
      expect(await nftContract.getUserLevel(user1.address)).to.equal(0);
    });

    it("Should handle free mint correctly", async function () {
      // First 10 mints should be free for this type
      await expect(nftContract.connect(user1).mint(0, { value: 0 })).to.emit(
        nftContract,
        "NFTMinted"
      );

      expect(await nftContract.getUserOwnedNFT(user1.address, 0)).to.be.true;
    });

    it("Should revert when minting inactive NFT type", async function () {
      await nftContract.updateNftTypeStatus(0, false);

      await expect(
        nftContract.connect(user1).mint(0, { value: TEST_NFT_TYPE.price })
      ).to.be.revertedWithCustomError(nftContract, "NFTTypeNotActive");
    });

    it("Should revert when user already minted", async function () {
      await nftContract.connect(user1).mint(0, { value: 0 });

      await expect(
        nftContract.connect(user1).mint(0, { value: TEST_NFT_TYPE.price })
      ).to.be.revertedWithCustomError(nftContract, "AlreadyMinted");
    });

    it("Should revert with insufficient payment", async function () {
      // Exhaust free mints first
      for (let i = 0; i < 10; i++) {
        await nftContract.connect(users[i]).mint(0, { value: 0 });
      }

      await expect(
        nftContract
          .connect(user1)
          .mint(0, { value: ethers.parseEther("0.005") })
      ).to.be.revertedWithCustomError(nftContract, "InsufficientPayment");
    });
  });

  describe("Whitelist Minting", function () {
    let merkleTree: MerkleTree;
    let merkleRoot: string;

    beforeEach(async function () {
      // Create whitelist with user1 and user2
      const whitelist = [user1.address, user2.address];
      const leaves = whitelist.map((addr) =>
        ethers.keccak256(ethers.solidityPacked(["address"], [addr]))
      );
      merkleTree = new MerkleTree(leaves, ethers.keccak256, {
        sortPairs: true,
      });
      merkleRoot = merkleTree.getRoot().toString("hex");

      await nftContract.setMerkleRoot("0x" + merkleRoot);
    });

    it("Should allow whitelist mint with valid proof", async function () {
      const leaf = ethers.keccak256(
        ethers.solidityPacked(["address"], [user1.address])
      );
      const proof = merkleTree.getHexProof(leaf);

      await expect(nftContract.connect(user1).whitelistMint(proof, 0)).to.emit(
        nftContract,
        "NFTMinted"
      );

      expect(await nftContract.getUserOwnedNFT(user1.address, 0)).to.be.true;
      expect(await nftContract.hasWhitelistMinted(user1.address)).to.be.true;
    });

    it("Should revert whitelist mint with invalid proof", async function () {
      const invalidProof = ["0x" + "0".repeat(64)];

      await expect(
        nftContract.connect(user1).whitelistMint(invalidProof, 0)
      ).to.be.revertedWithCustomError(nftContract, "InvalidProof");
    });

    it("Should prevent double whitelist minting", async function () {
      const leaf = ethers.keccak256(
        ethers.solidityPacked(["address"], [user1.address])
      );
      const proof = merkleTree.getHexProof(leaf);

      await nftContract.connect(user1).whitelistMint(proof, 0);

      await expect(
        nftContract.connect(user1).whitelistMint(proof, 0)
      ).to.be.revertedWithCustomError(nftContract, "AlreadyMinted");
    });
  });

  describe("Guard System", function () {
    it("Should require both guards for withdrawal", async function () {
      // Send some ETH to contract
      await owner.sendTransaction({
        to: await nftContract.getAddress(),
        value: ethers.parseEther("1"),
      });

      // Only one guard approves
      await nftContract.connect(guard1).guardPass(true);

      await expect(nftContract.withdraw()).to.be.revertedWithCustomError(
        nftContract,
        "NotApprovedByGuards"
      );

      // Both guards approve
      await nftContract.connect(guard2).guardPass(true);

      await expect(nftContract.withdraw()).to.not.be.reverted;
    });

    it("Should require both guards for ownership transfer", async function () {
      await nftContract.connect(guard1).guardPass(true);

      await expect(
        nftContract.connect(guard1).transferOwnership(user1.address)
      ).to.be.revertedWithCustomError(nftContract, "NotApprovedByGuards");

      await nftContract.connect(guard2).guardPass(true);

      await nftContract.connect(guard1).transferOwnership(user1.address);
      expect(await nftContract.owner()).to.equal(user1.address);
    });

    it("Should prevent non-guards from making decisions", async function () {
      await expect(
        nftContract.connect(user1).guardPass(true)
      ).to.be.revertedWithCustomError(nftContract, "CallerIsNotGuard");
    });
  });

  describe("Pause/Unpause", function () {
    it("Should allow owner to pause and unpause", async function () {
      await nftContract.pause();

      await expect(
        nftContract.connect(user1).mint(0, { value: 0 })
      ).to.be.revertedWithCustomError(nftContract, "EnforcedPause");

      await nftContract.unpause();

      await expect(nftContract.connect(user1).mint(0, { value: 0 })).to.not.be
        .reverted;
    });
  });

  describe("View Functions", function () {
    beforeEach(async function () {
      await nftContract.connect(user1).mint(0, { value: 0 });
    });

    it("Should return correct user level", async function () {
      expect(await nftContract.getUserLevel(user1.address)).to.equal(0);

      // Add and mint higher level NFT
      await nftContract.addNftType(TEST_NFT_TYPE_2);
      await nftContract.connect(user2).mint(1, { value: 0 });

      expect(await nftContract.getUserLevel(user2.address)).to.equal(1);
    });

    it("Should return all NFT types", async function () {
      await nftContract.addNftType(TEST_NFT_TYPE_2);

      const types = await nftContract.getNftTypes();
      expect(types.length).to.equal(2);
      expect(types[0].name).to.equal(TEST_NFT_TYPE.name);
      expect(types[1].name).to.equal(TEST_NFT_TYPE_2.name);
    });

    it("Should return correct NFT type counter", async function () {
      expect(await nftContract.getNftTypeCounter()).to.equal(1);

      await nftContract.addNftType(TEST_NFT_TYPE_2);
      expect(await nftContract.getNftTypeCounter()).to.equal(2);
    });
  });

  describe("Edge Cases", function () {
    it("Should handle max supply correctly", async function () {
      // Create NFT type with max supply of 1
      const limitedType = {
        ...TEST_NFT_TYPE,
        name: "Limited",
        maxSupply: 1,
        freeMintNumber: 1,
      };

      await nftContract.addNftType(limitedType);

      // First mint should succeed
      await nftContract.connect(user1).mint(1, { value: 0 });

      // Second mint should fail
      await expect(
        nftContract.connect(user2).mint(1, { value: 0 })
      ).to.be.revertedWithCustomError(nftContract, "MaxSupplyReached");
    });

    it("Should prevent renouncing ownership", async function () {
      await expect(nftContract.renounceOwnership()).to.be.revertedWith(
        "Renouncing ownership disabled"
      );
    });

    it("Should handle contract balance checks in withdrawal", async function () {
      await expect(nftContract.withdraw()).to.be.revertedWithCustomError(
        nftContract,
        "NoFundsToWithdraw"
      );
    });
  });

  describe("TokenURI", function () {
    it("Should return correct token URI", async function () {
      await nftContract.connect(user1).mint(0, { value: 0 });

      const tokenURI = await nftContract.tokenURI(1);
      expect(tokenURI).to.equal(TEST_NFT_TYPE.baseURI);
    });
  });

  describe("Gas Optimization Tests", function () {
    it("Should handle multiple users efficiently", async function () {
      const promises = [];
      for (let i = 0; i < 5; i++) {
        promises.push(nftContract.connect(users[i]).mint(0, { value: 0 }));
      }

      await Promise.all(promises);

      for (let i = 0; i < 5; i++) {
        expect(await nftContract.getUserOwnedNFT(users[i].address, 0)).to.be
          .true;
      }
    });
  });
});
