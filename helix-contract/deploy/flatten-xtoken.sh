path=flatten/xtoken-v3
mkdir -p $path
yarn flat contracts/mapping-token/v3/base/xTokenBacking.sol --output $path/xTokenBacking.sol
yarn flat contracts/mapping-token/v3/base/xTokenIssuing.sol --output $path/xTokenIssuing.sol
yarn flat contracts/mapping-token/v3/base/xTokenErc20.sol --output $path/xTokenErc20.sol
yarn flat contracts/mapping-token/v2/Guard.sol --output $path/Guard.sol
yarn flat contracts/messagers/MsglineMessager.sol --output $path/MsglineMessager.sol
