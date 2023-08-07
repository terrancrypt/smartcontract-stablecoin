# Stable Coin

1. Relative stability (tính ổn định tương đối): anchoref or pegged -> $USD ($1.00)
     Được neo vào USD
     Sử dụng Chainlink PriceFeed
     Tạo một function để chuyển đổi giá trị của ETH & BTC -> USD
2. Stability mechanism (Minting): Algorithmic (Cơ chế ổn định theo thuật toán, phi tập trung)
     Chỉ có thể mint stablecoin với đủ số tài sản đảm bảo được thế chấp vào trong giao thức
3. Collateral (tài sản đảm bảo): Exogenous - crypto (Tài sản đảm bảo nằm ngoài giao thức, là crypto)
     1. wBTC
     2. wETH


- calculate healthFactor function
- set helth factor if debt (dsc minted) is 0

1. invariants/properties của giao thức là gì?
2. 