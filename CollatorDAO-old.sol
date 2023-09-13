// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.0;
import "StakingInterface.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/Address.sol";

contract CollatorDAO is AccessControl{
    using SafeMath for uint256;

    //成员角色权限
    bytes32 private constant MEMBER = keccak256("MEMBER");
    //预编译地址
    address private constant precompileAddress = 0x0000000000000000000000000000000000000800;
    //预编译接口对象
    ParachainStaking private staking;
    //抵押总量
    uint256 private totalStake;
    //收集成员抵押量
    mapping(address => uint256) private memberStakes;
    //收集成员赎回量
    mapping(address => uint256) private memberRedeems;

    //技术服务比例
    uint private techProportion;
    //节点投资抵押最低下限
    uint private fundsDownLimit;
    //投资人数上限
    uint private investorUpLimit;
    //投资抵押上限
    uint private fundsUpLimit;
    //每人次投资抵押下限
    uint private perInvestDownLimit;
    //投票参与人数比例
    uint private voterProportion;
    //最低分配奖励额度
    uint private rewardDownLimit;
    //治理管理人
    address private governanceAdmin;

    //节点启动时间,时间戳
    uint256 private nodeStartDate;
    //技术服务费最低比例限制
    uint constant private techDownLimit = 20;
    //投票参与人数最低比例限制
    uint constant private voterDownLimit = 51;
    //治理开启标记
    bool private governanceFlag = false;
    //收集成员人数
    uint private memberTotal = 0;
    //实际收集成员人数
    uint private memberReal = 0;
    //收集成员地址
    mapping(uint => address) private memberAddrs;
    //收集成员奖励
    mapping(address => uint256) private memberRewards;
    //总奖励
    uint256 private totalReward = 0;
    //提案编号,顺序递增
    uint private currentNumber = 0;
    //提案对象
    struct GovernanceInfo{
        uint number; //提案编号
        uint256 startDate;//治理开始时间 
        uint256 endDate;//治理结束时间
        uint uintValue;//治理更新数值
        address addrValue;//治理人更新地址
        uint totalVoter;//应投票总人数,一般为收集人总人数
        uint approveVoter;//赞成票
        uint opposeVoter;//反对票
        bool success; //治理投票标记 true成功 false失败
    }
    //提案信息,governanceInfos[type]=info,type表示提案类型,info表示提案对象
    //提案类型:0技术服务比例 1节点投资抵押最低下限 2投资人数上限 3投资抵押上限 4每人次投资抵押下限 5投票参与人数最低比例 6最低分配奖励额度 7治理管理人 8节点解散
    mapping(uint => GovernanceInfo) private governanceInfos;
    //提案投票governanceVotes[number][adr]=state,number表示提案编号,adr表示投票人,state表示投票状态0未投票 1赞成 2反对
    mapping(uint => mapping (address => uint)) private governanceVotes;
    //合约sudo地址
    address private ownerAddress;

    constructor(uint _techProportion
                ,uint _fundsDownLimit
                ,uint _investorUpLimit
                ,uint _fundsUpLimit
                ,uint _perInvestDownLimit
                ,uint _voterProportion
                ,uint256 _nodeStartDate
                ,uint256 _rewardDownLimit
                ,address _techRewardAddr) {
        techProportion = _techProportion;
        fundsDownLimit = _fundsDownLimit;
        investorUpLimit = _investorUpLimit;
        fundsUpLimit =  _fundsUpLimit;
        perInvestDownLimit =  _perInvestDownLimit;
        voterProportion =  _voterProportion;
        nodeStartDate = _nodeStartDate;
        rewardDownLimit = _rewardDownLimit;
        governanceAdmin = msg.sender;
        ownerAddress = msg.sender;
        staking = ParachainStaking(precompileAddress);
        //技术服务奖励地址
        memberAddrs[memberTotal] = _techRewardAddr;
        memberTotal = memberTotal.add(1);
        _setupRole(MEMBER, _techRewardAddr);
    }

    modifier isGovernance() { 
        require(msg.sender == governanceAdmin,'sender is not admin!');
        require(governanceFlag,'governance is not start!');
        _;
    }

    modifier isOwner() { 
        require(msg.sender == ownerAddress,'sender is not owner!');
        require(!governanceFlag,'governance is start!');
        _;
    }

    //sudo权限,开启治理后失效
    function setParameter(uint _techProportion
                ,uint _fundsDownLimit
                ,uint _investorUpLimit
                ,uint _fundsUpLimit
                ,uint _perInvestDownLimit
                ,uint _voterProportion
                ,uint256 _nodeStartDate
                ,uint256 _rewardDownLimit) isOwner public{
        require(_techProportion >= techDownLimit,'_techProportion is illegal!');
        require(_voterProportion >= voterDownLimit,'_voterProportion is illegal!');
        techProportion = _techProportion;
        fundsDownLimit = _fundsDownLimit;
        investorUpLimit = _investorUpLimit;
        fundsUpLimit =  _fundsUpLimit;
        perInvestDownLimit =  _perInvestDownLimit;
        voterProportion =  _voterProportion;
        nodeStartDate = _nodeStartDate;
        rewardDownLimit = _rewardDownLimit;
    }

    //治理开启
    function _setGovern(GovernanceInfo memory _info,uint _uintValue,address _addrValue, uint256 _startDate,uint256 _endDate) private returns (GovernanceInfo memory){
        require(_startDate > block.timestamp && _startDate < _endDate,'date is illegal!');
        require(_info.startDate > block.timestamp || _info.endDate < block.timestamp,'Govern is governing!');
        if(_info.number == 0 || _info.endDate < block.timestamp){
            currentNumber = currentNumber.add(1);
            _info.number = currentNumber;
        }
        _info.startDate = _startDate;
        _info.endDate = _endDate;
        _info.uintValue = _uintValue;
        _info.addrValue = _addrValue;
        _info.totalVoter = memberReal;
        _info.approveVoter = 0;
        _info.opposeVoter = 0;
        _info.success = false;
        return _info;
    }

    //开启技术服务比例治理
    function startTPGovern(uint _techProportion,uint256 _startDate,uint256 _endDate) isGovernance public returns (uint){
        require(_techProportion >= techDownLimit,'_techProportion is illegal!');
        GovernanceInfo memory info = _setGovern(governanceInfos[0], _techProportion, address(0), _startDate, _endDate);
        governanceInfos[0] = info;
        return info.number;
    }

    //开启节点投资抵押最低下限治理
    function startPDLGovern(uint _fundsDownLimit,uint256 _startDate,uint256 _endDate) isGovernance public returns (uint){
        GovernanceInfo memory info = _setGovern(governanceInfos[1], _fundsDownLimit, address(0), _startDate, _endDate);
        governanceInfos[1] = info;
        return info.number;
    }

    //开启投资人数上限治理
    function startIULGovern(uint _investorUpLimit,uint256 _startDate,uint256 _endDate) isGovernance public returns (uint){
        GovernanceInfo memory info = _setGovern(governanceInfos[2], _investorUpLimit, address(0), _startDate, _endDate);
        governanceInfos[2] = info;
        return info.number;
    }

    //开启投资抵押上限治理
    function startFULGovern(uint _fundsUpLimit,uint256 _startDate,uint256 _endDate) isGovernance public returns (uint){
        GovernanceInfo memory info = _setGovern(governanceInfos[3], _fundsUpLimit, address(0), _startDate, _endDate);
        governanceInfos[3] = info;
        return info.number;
    }

    //开启每人次投资抵押下限治理
    function startPIDLGovern(uint _perInvestDownLimit,uint256 _startDate,uint256 _endDate) isGovernance public returns (uint){
        GovernanceInfo memory info = _setGovern(governanceInfos[4], _perInvestDownLimit, address(0), _startDate, _endDate);
        governanceInfos[4] = info;
        return info.number;
    }

    //开启投票参与人数比例治理
    function startVPGovern(uint _voterProportion,uint256 _startDate,uint256 _endDate) isGovernance public returns (uint){
        require(_voterProportion >= voterDownLimit,'_voterProportion is illegal!');
        GovernanceInfo memory info = _setGovern(governanceInfos[5], _voterProportion, address(0), _startDate, _endDate);
        governanceInfos[5] = info;
        return info.number;
    }

    //开启最低分配奖励额度治理
    function startRDGovern(uint _rewardDownLimit,uint256 _startDate,uint256 _endDate) isGovernance public returns (uint){
        GovernanceInfo memory info = _setGovern(governanceInfos[6], _rewardDownLimit, address(0), _startDate, _endDate);
        governanceInfos[6] = info;
        return info.number;
    }

    //开启治理人治理
    function startGAGovern(address _governanceAdmin,uint256 _startDate,uint256 _endDate) isGovernance public returns (uint){
        GovernanceInfo memory info = _setGovern(governanceInfos[7], 0, _governanceAdmin, _startDate, _endDate);
        governanceInfos[7] = info;
        return info.number;
    }

    //开启节点解散治理
    function startDBGovern(uint256 _startDate,uint256 _endDate) isGovernance public returns (uint){
        GovernanceInfo memory info = _setGovern(governanceInfos[8], 0, address(0), _startDate, _endDate);
        governanceInfos[8] = info;
        return info.number;
    }

    //治理投票
    function _setVote(GovernanceInfo memory _info,uint _number,uint _state) private returns (GovernanceInfo memory){
        require(_number > 0 && _info.number == _number,'_number is illegal!');
        require(_state > 0 && _state < 3,'_state is illegal!');
        require(_info.startDate <= block.timestamp && _info.endDate >= block.timestamp,'Govern is not start or governed!');
        require(governanceVotes[_number][msg.sender] == 0,'sender is voted!');
        governanceVotes[_number][msg.sender] = _state;
        if(_state == 1){
            _info.approveVoter = _info.approveVoter.add(1);
        }else if(_state == 2){
            _info.opposeVoter = _info.opposeVoter.add(1);
        }
        if(_info.approveVoter.mul(100).div(_info.totalVoter) >= voterProportion){
            _info.endDate = block.timestamp;
            _info.success = true;
        }
        return _info;
    }

    //技术服务比例治理投票
    function voteTPByNumber(uint _number,uint _state) public onlyRole(MEMBER) returns (bool){
        GovernanceInfo memory info = governanceInfos[0];
        info = _setVote(info, _number, _state);
        if(info.success){
            //治理成功
            techProportion = info.uintValue;
        }
        governanceInfos[0] = info;
        return true;
    }

    //节点投资抵押最低下限治理投票
    function votePDLByNumber(uint _number,uint _state) public onlyRole(MEMBER) returns (bool){
        GovernanceInfo memory info = governanceInfos[1];
        info = _setVote(info, _number, _state);
        if(info.success){
            //治理成功
            fundsDownLimit = info.uintValue;
        }
        governanceInfos[1] = info;
        return true;
    }

    //投资人数上限治理投票
    function voteIULByNumber(uint _number,uint _state) public onlyRole(MEMBER) returns (bool){
        GovernanceInfo memory info = governanceInfos[2];
        info = _setVote(info, _number, _state);
        if(info.success){
            //治理成功
            investorUpLimit = info.uintValue;
        }
        governanceInfos[2] = info;
        return true;
    }

    //投资抵押上限治理投票
    function voteFULByNumber(uint _number,uint _state) public onlyRole(MEMBER) returns (bool){
        GovernanceInfo memory info = governanceInfos[3];
        info = _setVote(info, _number, _state);
        if(info.success){
            //治理成功
            fundsUpLimit = info.uintValue;
        }
        governanceInfos[3] = info;
        return true;
    }

    //每人次投资抵押下限治理投票
    function votePIDLByNumber(uint _number,uint _state) public onlyRole(MEMBER) returns (bool){
        GovernanceInfo memory info = governanceInfos[4];
        info = _setVote(info, _number, _state);
        if(info.success){
            //治理成功
            perInvestDownLimit = info.uintValue;
        }
        governanceInfos[4] = info;
        return true;
    }

    //投票参与人数比例治理投票
    function voteVPByNumber(uint _number,uint _state) public onlyRole(MEMBER) returns (bool){
        GovernanceInfo memory info = governanceInfos[5];
        info = _setVote(info, _number, _state);
        if(info.success){
            //治理成功
            voterProportion = info.uintValue;
        }
        governanceInfos[5] = info;
        return true;
    }

    //最低分配奖励额度治理投票
    function voteNSDByNumber(uint _number,uint _state) public onlyRole(MEMBER) returns (bool){
        GovernanceInfo memory info = governanceInfos[6];
        info = _setVote(info, _number, _state);
        if(info.success){
            //治理成功
            rewardDownLimit = info.uintValue;
        }
        governanceInfos[6] = info;
        return true;
    }

    //治理人治理投票
    function voteRDByNumber(uint _number,uint _state) public onlyRole(MEMBER) returns (bool){
        GovernanceInfo memory info = governanceInfos[7];
        info = _setVote(info, _number, _state);
        if(info.success){
            //治理成功
            governanceAdmin = info.addrValue;
        }
        governanceInfos[7] = info;
        return true;
    }

    //分配奖励
    function _assign() private{
        uint techRewards = (address(this).balance).mul(techDownLimit).div(100);
        address redeemAddr = memberAddrs[0];
        memberRedeems[redeemAddr] = memberRedeems[redeemAddr].add(techRewards);
        memberRewards[redeemAddr] = memberRewards[redeemAddr].add(techRewards);
        uint stakeReward = (address(this).balance).sub(techRewards);
        for(uint i = 0; i < memberTotal; i++){
            redeemAddr = memberAddrs[i];
            uint reward = stakeReward.mul(memberStakes[redeemAddr]).div(totalStake);
            memberRedeems[redeemAddr] = memberRedeems[redeemAddr].add(reward);
            memberRewards[redeemAddr] = memberRewards[redeemAddr].add(reward);
        }
    }

    //节点解散治理投票
    function voteGAByNumber(uint _number,uint _state) public onlyRole(MEMBER) returns (bool){
        GovernanceInfo memory info = governanceInfos[8];
        info = _setVote(info, _number, _state);
        if(info.success){
            //从收集人赎回抵押
            governanceFlag = false;
            staking.leave_candidates(totalStake);
            for(uint i=0; i < memberTotal; i++){
                address redeemAddr = memberAddrs[i];
                memberRedeems[redeemAddr] = memberRedeems[redeemAddr].add(memberStakes[redeemAddr]);
                memberStakes[redeemAddr] = 0;
                _revokeRole(MEMBER, redeemAddr);
            }
            //存在未分配奖励
            if(address(this).balance > 0){
                totalReward = totalReward.add(address(this).balance);
                _assign();
            }
            governanceAdmin = ownerAddress;
            memberTotal = 1;
            memberReal = 0;
            totalReward = 0;
            totalStake = 0;            
        }
        governanceInfos[8] = info;
        return true;
    }

    //节点抵押
    function addStake() external payable {
        require(!governanceFlag,'governance is start!');
        require(block.timestamp < nodeStartDate,'nodeStartDate is expired!');
        require(msg.value >= perInvestDownLimit,'perInvestDownLimit is illegal!');
        require(totalStake + msg.value <= fundsUpLimit,'fundsUpLimit is illegal!');
        if(!hasRole(MEMBER, msg.sender)){
            require(memberReal <= investorUpLimit,'investorUpLimit is illegal!');
            memberAddrs[memberTotal] = msg.sender;
            memberTotal = memberTotal.add(1);
            memberReal = memberReal.add(1);
            _setupRole(MEMBER, msg.sender);
        }
        memberStakes[msg.sender] = memberStakes[msg.sender].add(msg.value);
        totalStake = totalStake.add(msg.value);        
    }

    //节点开启（关闭抵押）,治理开启,定时器触发
    function start() public isOwner{
        require(!governanceFlag,'governance is start!');
        require(block.timestamp >= nodeStartDate,'nodeStartDate is not start!');
        require(address(this).balance >= totalStake && totalStake >= fundsDownLimit ,'fundsDownLimit is illegal!');
        //开始进行收集人抵押
        staking.join_candidates(totalStake, staking.candidate_count());
        governanceFlag = true;
    }
    
    //赎回节点抵押
    function redeemStake(uint amount) public onlyRole(MEMBER){
        require(governanceFlag,'governance is not start!');
        require(amount > 0 && amount <= memberStakes[msg.sender],'amount is illegal!');
        require(totalStake - amount >= fundsDownLimit,'amount is too large,less than fundsDownLimit limit!');
        //从收集节点赎回抵押
        staking.candidate_bond_less(amount);
        memberStakes[msg.sender] = memberStakes[msg.sender].sub(amount);
        memberRedeems[msg.sender] = memberRedeems[msg.sender].add(amount);
        totalStake = totalStake.sub(amount);
        if(memberStakes[msg.sender] == 0){
            memberReal = memberReal.sub(1);
            _revokeRole(MEMBER, msg.sender);
        }
    }

    //申领赎回抵押
    function claimRedeem(address payable account) public onlyRole(MEMBER){
        require(account != address(0),'account is zero!');
        require(memberRedeems[msg.sender] > 0,'memberRedeems is not enough!');
        Address.sendValue(account, memberRedeems[msg.sender]);
        memberRedeems[msg.sender] = 0;
    }

    //奖励分配,定时器触发
    function assignRewards() public isOwner{
        require(governanceFlag,'governance is not start!');
        require(address(this).balance >= rewardDownLimit,'balance is not enough!');
        totalReward = totalReward.add(address(this).balance);
        _assign();
    }

    //抵押转让
    function fundsTransfer(address payable account) public onlyRole(MEMBER){
        require(account != address(0) && msg.sender != account,'account is illegal!');
        require(memberStakes[msg.sender] > 0,'memberStakes is not enough!');
        require(memberRedeems[msg.sender] == 0,'memberRedeems is not claim!');
        if(!hasRole(MEMBER, account)){
            memberAddrs[memberTotal] = account;
            memberTotal = memberTotal.add(1);
            _setupRole(MEMBER, account);
        }else{
            memberReal = memberReal.sub(1);
        }
        _revokeRole(MEMBER, msg.sender);
        memberStakes[account] = memberStakes[account].add(memberStakes[msg.sender]);
        memberStakes[msg.sender] = 0;
    }

    //获取节点当前余额
    function getBalance() public view returns(uint256){
        return address(this).balance;
    }

    //查看奖励
    function getReward() public view returns(uint256){
        return memberRewards[msg.sender];
    }

    //查看赎回
    function getRedeem() public view returns(uint256){
        return memberRedeems[msg.sender];
    }

    //查看抵押
    function getStake() public view returns(uint256){
        return memberStakes[msg.sender];
    }

    //查看节点总抵押
    function getTotalStake() public view returns(uint256){
        return totalStake;
    }

    //查看抵押所占比例
    function getStakeProportion() public view returns(uint256){
        return memberStakes[msg.sender].mul(100).div(totalStake);
    }

    //查看节点总奖励
    function getTotalReward() public view returns(uint256){
        return totalReward;
    }

    //查看年化奖励
    function getAnnualReward() public view returns(uint256){
        uint256 day = ((block.timestamp).sub(nodeStartDate)).div(1000 * 60 * 60 *24);
        return totalReward.mul(365 * 100).div(totalStake).div(day);
    }

    //查看节点成员人数
    function getMemberReal() public view returns(uint){
        return memberReal;
    }

    //查看节点开启日期
    function getNodeStartDate() public view returns(uint256){
        return nodeStartDate;
    }

    //查看节点状态 0未开启 1开启 2解散
    function getNodeState() public view returns(uint){
        uint state = governanceFlag ? 1: block.timestamp < nodeStartDate ? 0 : 2;
        return state;
    }

    struct NodeConfig{
        uint techProportion;
        uint fundsDownLimit;
        uint investorUpLimit;
        uint fundsUpLimit;
        uint perInvestDownLimit;
        uint voterProportion;
        uint rewardDownLimit;
        address governanceAdmin;
    }

    NodeConfig private nodeConfig;

    //查看节点配置信息
    function getNodeConfig() public returns(NodeConfig memory){
        nodeConfig.techProportion = techProportion;
        nodeConfig.fundsDownLimit = fundsDownLimit;
        nodeConfig.investorUpLimit = investorUpLimit;
        nodeConfig.fundsUpLimit = fundsUpLimit;
        nodeConfig.perInvestDownLimit = perInvestDownLimit;
        nodeConfig.voterProportion = voterProportion;
        nodeConfig.rewardDownLimit = rewardDownLimit;
        nodeConfig.governanceAdmin = governanceAdmin;
        return nodeConfig;
    }

    //查看节点治理信息
    function getGovernanceInfo(uint _type) public view returns(GovernanceInfo memory){
        return governanceInfos[_type];
    }
}