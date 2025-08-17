const { ethers } = require("ethers");
const dotenv = require("dotenv").config()

// Backend'in özel anahtarı
const privateKey = process.env.PRIVATE;
const wallet = new ethers.Wallet(privateKey);

async function signCompletion(userAddress, campaignId) {
    console.log("User Address -> ", userAddress)
    console.log("For Campaign Id -> ", campaignId)
    
    // ethers v6'da solidityKeccak256 yerine solidityPackedKeccak256 kullanılıyor
    const messageHash = ethers.solidityPackedKeccak256(
        ["address", "uint256"],
        [userAddress, campaignId]
    );

    console.log("Message Hash -> ", messageHash)
    const signature = await wallet.signMessage(ethers.getBytes(messageHash));
    console.log("Signature -> " , signature)
    console.log("Signature length -> " , signature.length)
    return { messageHash, signature };
}

function main() {
    signCompletion("0xAb8483F64d9C6d1EcF9b849Ae677dD3315835cb2", 1)
}

// main()


async function batchCompleteCampaigns() {
    // Backend'in özel anahtarı
    const privateKey = process.env.PRIVATE;
    const wallet = new ethers.Wallet(privateKey);

    
    // Kullanıcı adresi ve tamamlanacak kampanya ID'leri
    const userAddress = "0x7A0151479C6b9B4851427F35e452FDf53DDCD916";
    const campaignIds = [1, 2]; // Tamamlanacak kampanya ID'leri
    
    // Backend imzalaması gereken mesaj
    const message = ethers.solidityPackedKeccak256(
        ["address", "uint256[]"],
        [userAddress, campaignIds]
    );
    
    // Backend tarafında imzalama
    const signature = await wallet.signMessage(ethers.getBytes(message));
    
  console.log("Signature -> ", signature)
  console.log("Signature length -> ", signature.length)
  console.log("Message -> ", message)

}

batchCompleteCampaigns()
    .then(() => process.exit(0))
    .catch(error => {
        console.error("Hata:", error);
        process.exit(1);
    });