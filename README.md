# ActivateEarth NFT Contract 🌍

Modern ve güvenli ERC721 NFT kontratı - Çoklu NFT türleri, whitelist sistemi ve guard koruması ile.

## 📋 İçindekiler

- [🎯 Özellikler](#-özellikler)
- [🔒 Güvenlik Düzeltmeleri](#-güvenlik-düzeltmeleri)
- [🏗️ Kontrat Yapısı](#️-kontrat-yapısı)
- [📦 Deployment](#-deployment)
- [🚀 Kullanım](#-kullanım)
- [🔧 Geliştirici Rehberi](#-geliştirici-rehberi)
- [🛡️ Güvenlik](#️-güvenlik)

## 🎯 Özellikler

### ✨ Temel Özellikler

- **Çoklu NFT Türleri**: Farklı fiyat ve özelliklerde NFT türleri
- **Whitelist Mint**: Merkle Tree ile doğrulanmış whitelist sistemi
- **Free Mint**: Her NFT türü için ücretsiz mint imkanı
- **User Level System**: NFT türlerine göre otomatik seviye sistemi
- **Pause/Unpause**: Acil durumlar için durdurma sistemi
- **Guard System**: Kritik işlemler için çift guard onayı

### 🔐 Güvenlik Özellikleri

- **ReentrancyGuard**: Reentrancy saldırılarına karşı koruma
- **Access Control**: Fonksiyonlar için katı erişim kontrolü
- **Input Validation**: Tüm girişler için kapsamlı doğrulama
- **Custom Errors**: Gas-efficient hata mesajları
- **Guard Protection**: Withdraw ve ownership transfer için çift güvenlik

## 🔒 Güvenlik Düzeltmeleri

### ❌ Tespit Edilen Kritik Hatalar

1. **Input Validation Library Hatası**

   ```solidity
   // HATA: Eski kod - Validation mantığı tersine çevrili
   if (bytes(_input.name).length > 0 && bytes(_input.name).length <= 50)
       revert NameLengthInvalid(); // ❌ Valid değerler için hata fırlatıyor!

   // ✅ FİX: Düzeltildi
   if (bytes(_input.name).length == 0 || bytes(_input.name).length > 50)
       revert NameLengthInvalid();
   ```

2. **TokenURI Fonksiyonu Eksikliği**

   ```solidity
   // ✅ EklendI: ERC721URIStorage kullanılarak metadata desteği
   function _mintNFT(...) internal {
       _safeMint(to, tokenId);
       _setTokenURI(tokenId, nftType.baseURI); // 🆕
   }
   ```

3. **Free Mint Logic Hatası**

   ```solidity
   // ❌ HATA: Eski kod - Tutarsız kontroller
   if (nftType.freeMintNumber > 0 && !hasUserMinted[msg.sender][_nftTypeIndex]) {
       hasUserMinted[msg.sender][_nftTypeIndex] = true; // ❌ Çok erken set
   }

   // ✅ FİX: Ayrı tracking sistemi
   mapping(address => mapping(uint8 => bool)) public hasFreeMinted;
   ```

4. **Guard System İyileştirmeleri**
   ```solidity
   // ✅ Eklenen güvenlik kontrolleri
   constructor(address guard1, address guard2) {
       if (guard1 == guard2) revert InvalidGuardAddress(); // 🆕
   }
   ```

### 🛡️ Ek Güvenlik Geliştirmeleri

- ✅ **Comprehensive Error Handling**: Tüm hatalar için özel error types
- ✅ **Gas Optimizations**: Struct packing ve efficient mappings
- ✅ **Event Improvements**: Detailed events for tracking
- ✅ **Ownership Protection**: Renounce ownership disabled
- ✅ **Balance Checks**: Contract balance validations

## 🏗️ Kontrat Yapısı

### 📊 State Variables

```solidity
uint256 private _tokenIdCounter;      // Token ID counter
bytes32 private _merkleRoot;          // Whitelist merkle root
address private _guard1;              // First guard
address private _guard2;              // Second guard
uint8 private _nftTypeCounter;        // NFT type counter
bool private _guardDecision;          // Combined guard decision
```

### 🗂️ Mappings

```solidity
mapping(uint8 => NFTType) public nftTypes;                    // NFT türleri
mapping(address => uint8) public userLevel;                   // Kullanıcı seviyeleri
mapping(address => bool) public guardDecisions;               // Guard kararları
mapping(address => mapping(uint8 => bool)) public hasUserMinted;     // Mint durumu
mapping(address => bool) public hasWhitelistMinted;          // Whitelist mint durumu
mapping(address => mapping(uint8 => bool)) public hasFreeMinted;     // Free mint durumu
```

### 📝 Structs

```solidity
struct NFTType {
    uint8 id;
    string name;
    uint256 price;
    uint256 maxSupply;
    uint256 currentSupply;
    uint8 maxPoolNumber;
    string baseURI;
    bool isActive;
    uint16 freeMintNumber;
}
```

## 📦 Deployment

### 🔧 Gereksinimler

```bash
npm install --save-dev hardhat
npm install @openzeppelin/contracts
npm install @nomicfoundation/hardhat-toolbox
```

### 🚀 Deploy Adımları

1. **Hardhat Config Ayarlama**

   ```typescript
   // hardhat.config.ts
   require("@nomicfoundation/hardhat-toolbox");

   module.exports = {
     solidity: "0.8.19",
     networks: {
       sepolia: {
         url: "YOUR_ALCHEMY_URL",
         accounts: ["PRIVATE_KEY"],
       },
     },
   };
   ```

2. **Deploy Script Çalıştırma**

   ```bash
   # Local test
   npx hardhat run scripts/deploy.js --network localhost

   # Testnet deployment
   npx hardhat run scripts/deploy.js --network sepolia

   # Mainnet deployment
   npx hardhat run scripts/deploy.js --network mainnet
   ```

3. **Contract Verification**
   ```bash
   npx hardhat verify --network sepolia <CONTRACT_ADDRESS> <GUARD1_ADDRESS> <GUARD2_ADDRESS>
   ```

## 🚀 Kullanım

### 👑 Owner Fonksiyonları

#### NFT Türü Ekleme

```solidity
function addNftType(NftTypeInput memory _input) external onlyOwner

// Örnek kullanım
const nftType = {
  name: "Bronze Tier",
  baseURI: "https://api.example.com/metadata/bronze/",
  price: ethers.parseEther("0.01"),
  maxSupply: 1000,
  maxPoolNumber: 5,
  freeMintNumber: 100
};
await contract.addNftType(nftType);
```

#### Whitelist Ayarlama

```solidity
function setMerkleRoot(bytes32 _newMerkleRoot) external onlyOwner

// Merkle tree oluşturma
const whitelist = ["0x123...", "0x456..."];
const leaves = whitelist.map(addr => ethers.keccak256(ethers.solidityPacked(["address"], [addr])));
const tree = new MerkleTree(leaves, ethers.keccak256, { sortPairs: true });
await contract.setMerkleRoot(tree.getRoot());
```

### 🎮 Kullanıcı Fonksiyonları

#### Regular Mint

```solidity
// Ücretli mint
await contract.mint(nftTypeIndex, { value: price });

// Free mint (eğer varsa)
await contract.mint(nftTypeIndex, { value: 0 });
```

#### Whitelist Mint

```solidity
const proof = tree.getHexProof(leaf);
await contract.whitelistMint(proof, nftTypeIndex);
```

### 🛡️ Guard Fonksiyonları

#### Para Çekme Onayı

```solidity
// Her iki guard da onay vermeli
await contract.connect(guard1).guardPass(true);
await contract.connect(guard2).guardPass(true);
await contract.withdraw(); // Artık çekilebilir
```

## 🔧 Geliştirici Rehberi

### 🧪 Testing

```bash
# Tüm testleri çalıştır
npx hardhat test

# Belirli test dosyası
npx hardhat test test/ActivateEarthNFT.ts

# Coverage raporu
npx hardhat coverage
```

### 🔍 Contract İnteraction

#### Web3.js ile

```javascript
const Web3 = require("web3");
const web3 = new Web3("YOUR_RPC_URL");

const contract = new web3.eth.Contract(ABI, CONTRACT_ADDRESS);

// NFT mint et
await contract.methods.mint(0).send({
  from: userAddress,
  value: web3.utils.toWei("0.01", "ether"),
});
```

#### Ethers.js ile

```javascript
const { ethers } = require("ethers");
const provider = new ethers.providers.JsonRpcProvider("YOUR_RPC_URL");
const contract = new ethers.Contract(CONTRACT_ADDRESS, ABI, signer);

// User level kontrolü
const userLevel = await contract.getUserLevel(userAddress);
console.log(`User Level: ${userLevel}`);
```

### 📊 Event Monitoring

```javascript
// NFT mint olayını dinle
contract.on("NFTMinted", (to, tokenId, nftTypeIndex, event) => {
  console.log(`NFT ${tokenId} minted to ${to} (Type: ${nftTypeIndex})`);
});

// NFT türü ekleme olayını dinle
contract.on(
  "NFTTypeAdded",
  (id, name, price, maxSupply, maxPoolNumber, baseURI, event) => {
    console.log(`New NFT Type: ${name} (ID: ${id})`);
  }
);
```

## 🛡️ Güvenlik

### ⚠️ Dikkat Edilmesi Gerekenler

1. **Private Keys**: Private key'leri asla public repository'de tutmayın
2. **Guard Addresses**: Guard adreslerini güvenilir cüzdanlar olarak seçin
3. **Merkle Root**: Whitelist değiştirmeden önce merkle root'u güncelleyin
4. **Price Settings**: Fiyat ayarlarını dikkatli yapın (wei cinsinden)

### 🔒 Best Practices

```solidity
// ✅ İyi: Güvenli NFT türü oluşturma
const safeNFTType = {
  name: "Limited Edition",           // Max 50 karakter
  baseURI: "https://secure-api.com/", // HTTPS kullan
  price: ethers.parseEther("0.1"),   // Açık fiyat belirtimi
  maxSupply: 1000,                   // Makul supply
  maxPoolNumber: 10,                 // Pool limiti
  freeMintNumber: 50                 // Makul free mint
};

// ❌ Kötü: Güvensiz ayarlar
const unsafeNFTType = {
  name: "",                          // Boş isim
  baseURI: "http://insecure.com/",   // HTTP kullanımı
  price: 0,                          // Bedava ama kontrol yok
  maxSupply: 0,                      // Sınırsız supply
  maxPoolNumber: 0,                  // Geçersiz pool
  freeMintNumber: 2000               // Supply'dan fazla free mint
};
```

### 🚨 Acil Durum Prosedürleri

1. **Contract Pause**: `pause()` fonksiyonu ile tüm mintleri durdur
2. **Guard System**: Kritik işlemler için her iki guard onayı gerekli
3. **Ownership Transfer**: Sadece guardların onayı ile mümkün

## 📞 Destek

Herhangi bir sorun veya soru için:

- 📧 Email: security@activateearth.com
- 🐛 Issues: GitHub Issues bölümünü kullanın
- 📖 Docs: Contract dokümantasyonunu inceleyin

## 📄 Lisans

Bu proje MIT lisansı altında lisanslanmıştır.

---

**⚠️ UYARI**: Bu kontrat production kullanımı için hazırlanmıştır, ancak deploy etmeden önce:

1. Kapsamlı audit yaptırın
2. Test ağlarında detaylı test edin
3. Guard adreslerini güvenli seçin
4. Merkle tree'yi doğru oluşturun

**🎉 Bu kontrat şu iyileştirmelerle güçlendirilmiştir:**

- ✅ Tüm kritik güvenlik açıkları düzeltildi
- ✅ Modern Solidity best practices uygulandı
- ✅ Comprehensive error handling eklendi
- ✅ Gas optimizasyonları yapıldı
- ✅ Detaylı event tracking sistemi
- ✅ Production-ready deployment script'i
