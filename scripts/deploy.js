const hre = require("hardhat");

async function main() {
  console.log("🚀 ActivateEarthNFT Deployment başlıyor...\n");

  // Deploy öncesi bilgiler
  const [deployer] = await hre.ethers.getSigners();
  console.log("📍 Deployer adresi:", deployer.address);
  console.log("💰 Deployer bakiyesi:", hre.ethers.formatEther(await deployer.provider.getBalance(deployer.address)));

  // Guard adreslerini tanımla (production'da gerçek adresler kullanılmalı)
  const guard1Address = "0x70997970C51812dc3A010C7d01b50e0d17dc79C8"; // Hardhat test account 1
  const guard2Address = "0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC"; // Hardhat test account 2

  console.log("🛡️ Guard 1 Adresi:", guard1Address);
  console.log("🛡️ Guard 2 Adresi:", guard2Address);

  try {
    // Contract deploy
    console.log("\n📦 Contract deploy ediliyor...");
    const ActivateEarthNFT = await hre.ethers.getContractFactory("ActivateEarthNFT");
    const nft = await ActivateEarthNFT.deploy(guard1Address, guard2Address);
    
    await nft.waitForDeployment();
    const contractAddress = await nft.getAddress();
    
    console.log("✅ ActivateEarthNFT contract'ı deploy edildi!");
    console.log("📍 Contract Adresi:", contractAddress);

    // Contract doğrulama (Etherscan için)
    if (hre.network.name !== "hardhat" && hre.network.name !== "localhost") {
      console.log("\n🔍 Contract verification bekleniyor...");
      await new Promise(resolve => setTimeout(resolve, 30000)); // 30 saniye bekle

      try {
        await hre.run("verify:verify", {
          address: contractAddress,
          constructorArguments: [guard1Address, guard2Address],
        });
        console.log("✅ Contract verify edildi!");
      } catch (error) {
        console.log("⚠️ Verify hatası:", error.message);
      }
    }

    // Örnek NFT type oluştur
    console.log("\n🎨 Örnek NFT type'ları oluşturuluyor...");
    
    const nftTypes = [
      {
        name: "Bronze Tier",
        baseURI: "https://api.activateearth.com/metadata/bronze/",
        price: hre.ethers.parseEther("0.01"), // 0.01 ETH
        maxSupply: 1000,
        maxPoolNumber: 5,
        freeMintNumber: 100
      },
      {
        name: "Silver Tier",
        baseURI: "https://api.activateearth.com/metadata/silver/",
        price: hre.ethers.parseEther("0.05"), // 0.05 ETH
        maxSupply: 500,
        maxPoolNumber: 10,
        freeMintNumber: 50
      },
      {
        name: "Gold Tier",
        baseURI: "https://api.activateearth.com/metadata/gold/",
        price: hre.ethers.parseEther("0.1"), // 0.1 ETH
        maxSupply: 100,
        maxPoolNumber: 20,
        freeMintNumber: 10
      }
    ];

    for (let i = 0; i < nftTypes.length; i++) {
      const tx = await nft.addNftType(nftTypes[i]);
      await tx.wait();
      console.log(`✅ NFT Type ${i} (${nftTypes[i].name}) oluşturuldu`);
    }

    // Merkle root ayarla (örnek - production'da gerçek merkle root kullanılmalı)
    const exampleMerkleRoot = "0x1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef";
    const merkleRootTx = await nft.setMerkleRoot(exampleMerkleRoot);
    await merkleRootTx.wait();
    console.log("✅ Merkle root ayarlandı");

    // Deployment özeti
    console.log("\n" + "=".repeat(60));
    console.log("🎉 DEPLOYMENT TAMAMLANDI!");
    console.log("=".repeat(60));
    console.log("📍 Contract Adresi:", contractAddress);
    console.log("🛡️ Guard 1:", guard1Address);
    console.log("🛡️ Guard 2:", guard2Address);
    console.log("🎨 Oluşturulan NFT Type Sayısı:", nftTypes.length);
    console.log("🔐 Merkle Root:", exampleMerkleRoot);
    console.log("🌐 Network:", hre.network.name);
    console.log("⛽ Gas kullanımı hesaplanıyor...");
    
    // Son kontroller
    const owner = await nft.owner();
    const typeCounter = await nft.getNftTypeCounter();
    const guards = await nft.getGuards();
    
    console.log("\n📊 Contract Durumu:");
    console.log("👑 Owner:", owner);
    console.log("🔢 NFT Type Sayısı:", typeCounter.toString());
    console.log("🛡️ Guards:", guards[0], guards[1]);
    
    console.log("\n✨ Contract başarıyla deploy edildi ve kullanıma hazır!");

    // Test mint örneği (sadece test ağlarında)
    if (hre.network.name === "hardhat" || hre.network.name === "localhost") {
      console.log("\n🧪 Test mint gerçekleştiriliyor...");
      try {
        const mintTx = await nft.mint(0, { value: hre.ethers.parseEther("0.01") });
        await mintTx.wait();
        console.log("✅ Test mint başarılı!");
        
        const userLevel = await nft.getUserLevel(deployer.address);
        console.log("📈 Deployer'ın seviyesi:", userLevel.toString());
      } catch (error) {
        console.log("⚠️ Test mint hatası:", error.message);
      }
    }

  } catch (error) {
    console.error("❌ Deployment hatası:", error);
    process.exitCode = 1;
  }
}

main().catch((error) => {
  console.error("❌ Script hatası:", error);
  process.exitCode = 1;
});